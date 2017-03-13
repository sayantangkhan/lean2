;;; lean-mode.el --- Emacs mode for Lean theorem prover
;;
;; Copyright (c) 2013, 2014 Microsoft Corporation. All rights reserved.
;; Copyright (c) 2014, 2015 Soonho Kong. All rights reserved.
;;
;; Author: Leonardo de Moura <leonardo@microsoft.com>
;;         Soonho Kong       <soonhok@cs.cmu.edu>
;; Maintainer: Soonho Kong   <soonhok@cs.cmu.edu>
;; Created: Jan 09, 2014
;; Keywords: languages
;; Version: 0.1
;; URL: https://github.com/leanprover/lean/blob/master/src/emacs
;;
;; Released under Apache 2.0 license as described in the file LICENSE.
;;
(require 'pcase)
(require 'lean-require)
(require 'eri)
(require 'lean-variable)
(require 'lean-util)
(require 'lean-settings)
(require 'lean-flycheck)
(require 'lean-input)
(require 'lean-type)
(require 'lean-tags)
(require 'lean-option)
(require 'lean-syntax)
(require 'lean-company)
(require 'lean-changes)
(require 'lean-server)
(require 'lean-project)

(defun lean-compile-string (exe-name args file-name)
  "Concatenate exe-name, args, and file-name"
  (format "%s %s %s" exe-name args file-name))

(defun lean-create-temp-in-system-tempdir (file-name prefix)
  "Create a temp lean file and return its name"
  (make-temp-file (or prefix "flymake") nil (f-ext file-name)))

(defun lean-execute (&optional arg)
  "Execute Lean in the current buffer"
  (interactive)
  (setq arg (concat (lean-option-string) " " arg))
  (when (called-interactively-p)
    (setq arg (read-string "arg: " arg)))
  (let ((target-file-name
         (or
          (buffer-file-name)
          (flymake-init-create-temp-buffer-copy 'lean-create-temp-in-system-tempdir))))
    (compile (lean-compile-string
              (shell-quote-argument (f-full (lean-get-executable lean-executable-name)))
              (or arg "")
              (shell-quote-argument (f-full target-file-name))))))

(defvar g-lean-exec-at-pos-buf ""
  "Temp buffer to save the output from lean server (for lean-exec-at-pos)")

(defun lean-exec-at-pos-extract-body (str)
  "Extract the body of LEAN_INFORMATION"
  (let ((header "LEAN_INFORMATION")
        (footer "END_LEAN_INFORMATION"))
    (cond
     ((and (s-contains? header str)
           (s-contains? footer str))
      (let*
          ((begin-regex (eval `(rx line-start ,header (* not-newline) line-end)))
           (end-regex   (eval `(rx line-start (group ,footer) line-end)))
           (pre-body-post
            (lean-server-split-buffer str begin-regex end-regex))
           (body (cadr pre-body-post))
           (lines (s-lines body)))
        (s-join "\n" (-butlast (-drop 1 lines)))))
     (t ""))))

(defun lean-exec-at-pos-sentinel (process event)
  "Sentinel function used for lean-exec-at-pos. It does the two
  things: A. display the process buffer, B. scroll to the top"
  (when (eq (process-status process) 'exit)
    (let ((b (process-buffer process)))
      (with-current-buffer b
        (lean-info-mode)
        (insert-string (lean-exec-at-pos-extract-body
                        g-lean-exec-at-pos-buf)))
      (display-buffer b)
      ;; Temporary Hack to scroll to the top
      ;; See https://github.com/leanprover/lean/issues/499#issuecomment-125285231
      (set-window-point (get-buffer-window b) 0))))

(defun lean-exec-at-pos-filter (process string)
  "Filter function for lean-exec-at-pos. It append the string to
  g-lean-exec-at-pos-buf variable"
  (setq g-lean-exec-at-pos-buf (s-append string g-lean-exec-at-pos-buf)))

(defun lean-start-process (args filter-fn sentinel-fn)
  "Start process with filter and sentinel functions"
  (let ((p (apply 'start-process args)))
    (set-process-filter p filter-fn)
    (set-process-sentinel p sentinel-fn)
    (set-process-coding-system p 'utf-8 'utf-8)
    (set-process-query-on-exit-flag p nil)))

(defvar lean-exec-at-pos-timer nil
  "Timer for `lean-exec-at-pos-with-timer' to reschedule itself, or nil.")

(defun lean-exec-at-pos-with-timer (args filter-fn sentinel-fn)
  "Run lean-exec-at-pos with a timer. It waits until flycheck is finished."
 (when lean-exec-at-pos-timer
    (cancel-timer lean-exec-at-pos-timer))
 (cond ((flycheck-running-p)
        (message "flycheck-lean is running...")
         (setq lean-exec-at-pos-timer
               (run-at-time
                lean-exec-at-pos-wait-time nil
                `(lambda () (lean-exec-at-pos-with-timer ',args ',filter-fn ',sentinel-fn)))))
        (t
         (message "flycheck is over, start lean-process...")
         (lean-start-process args filter-fn sentinel-fn))))

(defun lean-exec-at-pos (process-name process-buffer-name &rest options)
  "Execute Lean by providing current position with optional
agruments. The output goes to 'process-buffer-name' buffer, which
will be flushed everytime it's executed."
  (setq g-lean-exec-at-pos-buf "")
  ;; Kill process-name if exists
  (let ((current-process (get-process process-name)))
    (when current-process
      (kill-process)))
  ;; Flush process-buffer
  (let ((process-buffer (get-buffer process-buffer-name)))
    (when process-buffer
      (with-current-buffer process-buffer
        (erase-buffer))))
  ;; Start process
  (let* ((target-file-name
          (or
           ;; Only use file-name if the current buffer is not modified
           (and (not (buffer-modified-p)) (buffer-file-name))
           (flymake-init-create-temp-buffer-copy 'lean-create-temp-in-system-tempdir)))
         (cache-file-name
          (s-concat (f-no-ext target-file-name)
                    ".clean"))
         (cache-option
          ;; Cache is only used when we use a non-temporary file
          (if (s-equals? (buffer-file-name) target-file-name)
              `("--cache" ,cache-file-name)
            '()))
         (lean-mode-option
          (pcase (lean-choose-minor-mode-based-on-extension)
            (`standard "--lean")
            (`hott     "--hlean")))
         (default-directory (or (lean-project-find-root) default-directory))
         (process-args (append `(,process-name
                                 ,process-buffer-name
                                 ,(lean-get-executable lean-executable-name)
                                 ,lean-mode-option
                                 "--dir"
                                 ,(f-dirname (buffer-file-name))
                                 "--line"
                                 ,(int-to-string (line-number-at-pos))
                                 "--col"
                                 ,(int-to-string (current-column)))
                               options
                               cache-option
                               `(,target-file-name))))
    (cond ((and cache-option (flycheck-running-p))
           ;; Cache is used and flycheck is running
           (lean-exec-at-pos-with-timer process-args 'lean-exec-at-pos-filter 'lean-exec-at-pos-sentinel))
          (t
           ;; start lean-process immediately
           (lean-start-process process-args 'lean-exec-at-pos-filter 'lean-exec-at-pos-sentinel)))))

(defun lean-show-goal-at-pos ()
  "Show goal at the current point. If the current point is a
placeholder, call lean-server with --hole option, otherwise call
  lean-server with --goal option"
  (interactive)
  (cond ((and (eq (char-after) ?_)               ;; 1. at _
              (not (lean-in-comment-p))          ;; 2. not in comment
              (or (bolp)                         ;; 3. either beginning of line
                  (let ((cb (char-before)))      ;;    or whitespace
                    (or (char-equal cb ?\s)
                        (char-equal cb ?\t)
                        (char-equal cb ?\n)
                        (char-equal cb ?\r)))))
              (lean-exec-at-pos "lean-hole" "*Lean Goal*" "--hole"))
         (t
          (lean-exec-at-pos "lean-goal" "*Lean Goal*" "--goal"))))
(defun lean-show-id-keyword-info ()
  "Show ID/Keyword Information at the position"
  (interactive)
  (lean-exec-at-pos
   "lean-print-id-keyword-info"
   "*Lean Print*"
   "--info"))

(defun lean-std-exe ()
  (interactive)
  (lean-execute))

(defun lean-check-expansion ()
  (interactive)
  (save-excursion
    (if (looking-at (rx symbol-start "_")) t
      (if (looking-at "\\_>") t
        (backward-char 1)
        (if (looking-at "\\.") t
          (backward-char 1)
          (if (looking-at "->") t nil))))))

(defun lean-tab-indent ()
  (cond ((looking-back (rx line-start (* white)))
         (eri-indent))
        (t (indent-for-tab-command))))

(defun lean-tab-indent-or-complete ()
  (interactive)
  (if (minibufferp)
      (minibuffer-complete)
    (cond ((and lean-company-use (company-lean--check-prefix))
           (company-complete-common))
          (lean-company-use (lean-tab-indent))
          ((lean-check-expansion)
           (completion-at-point-functions))
          (t (lean-tab-indent)))))

(defun lean-set-keys ()
  (local-set-key lean-keybinding-std-exe1                  'lean-std-exe)
  (local-set-key lean-keybinding-std-exe2                  'lean-std-exe)
  (local-set-key lean-keybinding-show-key                  'quail-show-key)
  (local-set-key lean-keybinding-set-option                'lean-set-option)
  (local-set-key lean-keybinding-eval-cmd                  'lean-eval-cmd)
  (local-set-key lean-keybinding-show-type                 'lean-show-type)
  (local-set-key lean-keybinding-fill-placeholder          'lean-fill-placeholder)
  (local-set-key lean-keybinding-server-restart-process    'lean-server-restart-process)
  (local-set-key lean-keybinding-find-tag                  'lean-find-tag)
  (local-set-key lean-keybinding-tab-indent-or-complete    'lean-tab-indent-or-complete)
  (local-set-key lean-keybinding-lean-show-goal-at-pos     'lean-show-goal-at-pos)
  (local-set-key lean-keybinding-lean-show-id-keyword-info 'lean-show-id-keyword-info)
  (local-set-key lean-keybinding-lean-next-error-mode      'lean-next-error-mode)
  )

(defun lean-define-key-binding (key cmd)
  (local-set-key key `(lambda () (interactive) ,cmd)))

(define-abbrev-table 'lean-abbrev-table
  '())

(defvar lean-mode-map (make-sparse-keymap)
  "Keymap used in Lean mode")

(easy-menu-define lean-mode-menu lean-mode-map
  "Menu for the Lean major mode"
  `("Lean"
    ["Execute lean"         lean-execute                      t]
    ["Create a new project" (call-interactively 'lean-project-create) (not (lean-project-inside-p))]
    "-----------------"
    ["Show type info"       lean-show-type                    (and lean-eldoc-use eldoc-mode)]
    ["Show goal"            lean-show-goal-at-pos             t]
    ["Show id/keyword info" lean-show-id-keyword-info         t]
    ["Fill a placeholder"   lean-fill-placeholder             (looking-at  (rx symbol-start "_"))]
    ["Find tag at point"    lean-find-tag                     t]
    ["Global tag search"    lean-global-search                t]
    "-----------------"
    ["Run flycheck"         flycheck-compile                  (and lean-flycheck-use flycheck-mode)]
    ["List of errors"       flycheck-list-errors              (and lean-flycheck-use flycheck-mode)]
    "-----------------"
    ["Clear all cache"      lean-clear-cache                  t]
    ["Kill lean process"    lean-server-kill-process          t]
    ["Restart lean process" lean-server-restart-process       t]
    "-----------------"
    ("Configuration"
     ["Use flycheck (on-the-fly syntax check)"
      lean-toggle-flycheck-mode :active t :style toggle :selected flycheck-mode]
     ["Show type at point"
      lean-toggle-eldoc-mode :active t :style toggle :selected eldoc-mode]
     ["Show next error in dedicated buffer"
      lean-next-error-mode :active t :style toggle :selected lean-next-error-mode])
    "-----------------"
    ["Customize lean-mode" (customize-group 'lean)            t]))

(defconst lean-hooks-alist
  '(
    ;; Handle events that may start automatic syntax checks
    (before-save-hook                    . lean-whitespace-cleanup)
    (after-save-hook                     . lean-server-after-save)
    ;; ;; Handle events that may triggered pending deferred checks
    ;; (window-configuration-change-hook . lean-perform-deferred-syntax-check)
    ;; (post-command-hook                . lean-perform-deferred-syntax-check)
    ;; ;; Teardown Lean whenever the buffer state is about to get lost, to
    ;; ;; clean up temporary files and directories.
    ;; (kill-buffer-hook                 . lean-teardown)
    ;; (change-major-mode-hook           . lean-teardown)
    (before-revert-hook                  . lean-before-revert)
    (after-revert-hook                   . lean-after-revert)
    ;; ;; Update the error list if necessary
    ;; (post-command-hook                . lean-error-list-update-source)
    ;; (post-command-hook                . lean-error-list-highlight-errors)
    ;; ;; Show or hide error popups after commands
    ;; (post-command-hook                . lean-display-error-at-point-soon)
    ;; (post-command-hook                . lean-hide-error-buffer)
    )
  "Hooks which lean-mode needs to hook in.

The `car' of each pair is a hook variable, the `cdr' a function
to be added or removed from the hook variable if Flycheck mode is
enabled and disabled respectively.")

(when lean-follow-changes
  (add-to-list 'lean-hooks-alist '(after-change-functions  . lean-after-change-function))
  (add-to-list 'lean-hooks-alist '(before-change-functions . lean-before-change-function)))

(defun lean-mode-setup ()
  "Default lean-mode setup"
  ;; Flycheck
  (when lean-flycheck-use
    (lean-flycheck-turn-on)
    (add-hook 'flycheck-after-syntax-check-hook 'lean-flycheck-delete-temporaries nil t))
  ;; Draw a vertical line for rule-column
  (when (and lean-rule-column
             lean-show-rule-column-method)
    (cl-case lean-show-rule-column-method
      ('vline (require 'fill-column-indicator)
              (setq fci-rule-column lean-rule-column)
              (setq fci-rule-color lean-rule-color)
              (fci-mode t))))
  ;; eldoc
  (when lean-eldoc-use
    (set (make-local-variable 'eldoc-documentation-function)
         'lean-eldoc-documentation-function)
    (eldoc-mode t))
  ;; company-mode
  (when lean-company-use
    (company-lean-hook))
  ;; choose minor mode -- Standard / HoTT
  (let ((minor-mode (lean-choose-minor-mode-based-on-extension)))
    (cond
     ((eq minor-mode 'hott) (lean-hott-mode) )
     ((eq minor-mode 'standard) (lean-standard-mode)))))

;; Define Minor mode
;;  - Standard
;;  - HoTT
(define-minor-mode lean-standard-mode
  "Minor mode for standard Lean."
  :init-value nil
  :lighter " [Standard]"
  :group 'lean
  :require 'lean)

(define-minor-mode lean-hott-mode
  "Minor mode for HoTT Lean."
  :init-value nil
  :lighter " [HoTT]"
  :group 'lean
  :require 'lean)

;; Automode List
;;;###autoload
(define-derived-mode lean-mode prog-mode "Lean"
  "Major mode for Lean
     \\{lean-mode-map}
Invokes `lean-mode-hook'.
"
  :syntax-table lean-syntax-table
  :abbrev-table lean-abbrev-table
  :group 'lean
  (set (make-local-variable 'comment-start) "--")
  (set (make-local-variable 'comment-start-skip) "[-/]-[ \t]*")
  (set (make-local-variable 'comment-end) "")
  (set (make-local-variable 'comment-end-skip) "[ \t]*\\(-/\\|\\s>\\)")
  (set (make-local-variable 'comment-padding) 1)
  (set (make-local-variable 'comment-use-syntax) t)
  (set (make-local-variable 'font-lock-defaults) lean-font-lock-defaults)
  (set (make-local-variable 'indent-tabs-mode) nil)
  (set 'compilation-mode-font-lock-keywords '())
  (set-input-method "Lean")
  (set (make-local-variable 'lisp-indent-function)
       'common-lisp-indent-function)
  (lean-set-keys)
  (if (fboundp 'electric-indent-local-mode)
      (electric-indent-local-mode -1))
  ;; (abbrev-mode 1)
  (pcase-dolist (`(,hook . ,fn) lean-hooks-alist)
    (add-hook hook fn nil 'local))
  (lean-mode-setup))

;;; Automatically update TAGS file without asking
(setq tags-revert-without-query t)

;; Automatically use lean-mode for .lean files.
;;;###autoload
(push '("\\.lean$" . lean-mode) auto-mode-alist)
(push '("\\.hlean$" . lean-mode) auto-mode-alist)

;; Use utf-8 encoding
;;;### autoload
(modify-coding-system-alist 'file "\\.lean\\'" 'utf-8)
(modify-coding-system-alist 'file "\\.hlean\\'" 'utf-8)

;; Flycheck init
;(when lean-flycheck-use
  ;(require 'flycheck)
  ;(eval-after-load 'flycheck
    ;'(lean-flycheck-init)))

;; Lean Info Mode (for "*lean-info*" buffer)
;; Automode List
;;;###autoload
(define-derived-mode lean-info-mode prog-mode "Lean-Info"
  "Major mode for Lean Info Buffer"
  :syntax-table lean-syntax-table
  :group 'lean
  (set (make-local-variable 'font-lock-defaults) lean-info-font-lock-defaults)
  (set (make-local-variable 'indent-tabs-mode) nil)
  (set 'compilation-mode-font-lock-keywords '())
  (set-input-method "Lean")
  (set (make-local-variable 'lisp-indent-function)
       'common-lisp-indent-function))

(provide 'lean-mode)
;;; lean-mode.el ends here
