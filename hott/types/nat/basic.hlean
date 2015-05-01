/-
Copyright (c) 2014 Floris van Doorn. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Module: types.nat.basic
Authors: Floris van Doorn, Leonardo de Moura, Jeremy Avigad

Basic operations on the natural numbers.

-/
import algebra.binary
open eq sum sigma prod binary

namespace nat

/- a variant of add, defined by recursion on the first argument -/

definition addl (x y : ℕ) : ℕ :=
nat.rec y (λ n r, succ r) x
infix `⊕`:65 := addl

theorem addl_succ_right (n m : ℕ) : n ⊕ succ m = succ (n ⊕ m) :=
nat.rec_on n
  rfl
  (λ n₁ ih, calc
    succ n₁ ⊕ succ m = succ (n₁ ⊕ succ m)   : rfl
             ...     = succ (succ (n₁ ⊕ m)) : ih
             ...     = succ (succ n₁ ⊕ m)   : rfl)

theorem add_eq_addl (x : ℕ) : ∀y, x + y = x ⊕ y :=
nat.rec_on x
  (λ y, nat.rec_on y
    rfl
    (λ y₁ ih, calc
      zero + succ y₁ = succ (zero + y₁)  : rfl
              ...    = succ (zero ⊕ y₁) : {ih}
              ...    = zero ⊕ (succ y₁) : rfl))
  (λ x₁ ih₁ y, nat.rec_on y
    (calc
      succ x₁ + zero  = succ (x₁ + zero)  : rfl
                  ... = succ (x₁ ⊕ zero) : {ih₁ zero}
                  ... = succ x₁ ⊕ zero   : rfl)
    (λ y₁ ih₂, calc
      succ x₁ + succ y₁ = succ (succ x₁ + y₁) : rfl
                   ...  = succ (succ x₁ ⊕ y₁) : {ih₂}
                   ...  = succ x₁ ⊕ succ y₁   : addl_succ_right))

/- successor and predecessor -/

theorem succ_ne_zero (n : ℕ) : succ n ≠ 0 :=
by contradiction

-- add_rewrite succ_ne_zero

theorem pred_zero : pred 0 = 0 :=
rfl

theorem pred_succ (n : ℕ) : pred (succ n) = n :=
rfl

theorem eq_zero_or_eq_succ_pred (n : ℕ) : n = 0 ⊎ n = succ (pred n) :=
nat.rec_on n
  (sum.inl rfl)
  (take m IH, sum.inr
    (show succ m = succ (pred (succ m)), from ap succ !pred_succ⁻¹))

theorem exists_eq_succ_of_ne_zero {n : ℕ} (H : n ≠ 0) : Σk : ℕ, n = succ k :=
⟨_, sum.rec_on (eq_zero_or_eq_succ_pred n) (λH2, absurd H2 H) function.id⟩

theorem succ_inj {n m : ℕ} (H : succ n = succ m) : n = m :=
lift.down (nat.no_confusion H (λe, e))

theorem succ_ne_self {n : ℕ} : succ n ≠ n :=
nat.rec_on n
  (take H : 1 = 0,
    have ne : 1 ≠ 0, from !succ_ne_zero,
    absurd H ne)
  (take k IH H, IH (succ_inj H))

theorem discriminate {B : Type} {n : ℕ} (H1: n = 0 → B) (H2 : ∀m, n = succ m → B) : B :=
have H : n = n → B, from nat.cases_on n H1 H2,
H rfl

theorem two_step_induction_on {P : ℕ → Type} (a : ℕ) (H1 : P 0) (H2 : P 1)
    (H3 : ∀ (n : ℕ) (IH1 : P n) (IH2 : P (succ n)), P (succ (succ n))) : P a :=
have stronger : P a × P (succ a), from
  nat.rec_on a
    (H1, H2)
    (take k IH,
      have IH1 : P k, from pr1 IH,
      have IH2 : P (succ k), from pr2 IH,
        (IH2, (H3 k IH1 IH2))),
  pr1 stronger

theorem sub_induction {P : ℕ → ℕ → Type} (n m : ℕ) (H1 : ∀m, P 0 m)
   (H2 : ∀n, P (succ n) 0) (H3 : ∀n m, P n m → P (succ n) (succ m)) : P n m :=
have general : ∀m, P n m, from nat.rec_on n
  (take m : ℕ, H1 m)
  (take k : ℕ,
    assume IH : ∀m, P k m,
    take m : ℕ,
    nat.cases_on m (H2 k) (take l, (H3 k l (IH l)))),
general m

/- addition -/

theorem add_zero (n : ℕ) : n + 0 = n :=
rfl

theorem add_succ (n m : ℕ) : n + succ m = succ (n + m) :=
rfl

theorem zero_add (n : ℕ) : 0 + n = n :=
nat.rec_on n
    !add_zero
    (take m IH, show 0 + succ m = succ m, from
      calc
        0 + succ m = succ (0 + m) : add_succ
               ... = succ m       : IH)

theorem succ_add (n m : ℕ) : (succ n) + m = succ (n + m) :=
nat.rec_on m
    (!add_zero ▸ !add_zero)
    (take k IH, calc
      succ n + succ k = succ (succ n + k)    : add_succ
                  ... = succ (succ (n + k))  : IH
                  ... = succ (n + succ k)    : add_succ)

theorem add.comm (n m : ℕ) : n + m = m + n :=
nat.rec_on m
    (!add_zero ⬝ !zero_add⁻¹)
    (take k IH, calc
        n + succ k = succ (n+k)   : add_succ
               ... = succ (k + n) : IH
               ... = succ k + n   : succ_add)

theorem succ_add_eq_succ_add (n m : ℕ) : succ n + m = n + succ m :=
!succ_add ⬝ !add_succ⁻¹

theorem add.assoc (n m k : ℕ) : (n + m) + k = n + (m + k) :=
nat.rec_on k
    (!add_zero ▸ !add_zero)
    (take l IH,
      calc
        (n + m) + succ l = succ ((n + m) + l)  : add_succ
                     ... = succ (n + (m + l))  : IH
                     ... = n + succ (m + l)    : add_succ
                     ... = n + (m + succ l)    : add_succ)

theorem add.left_comm (n m k : ℕ) : n + (m + k) = m + (n + k) :=
left_comm add.comm add.assoc n m k

theorem add.right_comm (n m k : ℕ) : n + m + k = n + k + m :=
right_comm add.comm add.assoc n m k

theorem add.cancel_left {n m k : ℕ} : n + m = n + k → m = k :=
nat.rec_on n
  (take H : 0 + m = 0 + k,
    !zero_add⁻¹ ⬝ H ⬝ !zero_add)
  (take (n : ℕ) (IH : n + m = n + k → m = k) (H : succ n + m = succ n + k),
    have H2 : succ (n + m) = succ (n + k),
    from calc
      succ (n + m) = succ n + m   : succ_add
               ... = succ n + k   : H
               ... = succ (n + k) : succ_add,
    have H3 : n + m = n + k, from succ_inj H2,
    IH H3)

theorem add.cancel_right {n m k : ℕ} (H : n + m = k + m) : n = k :=
have H2 : m + n = m + k, from !add.comm ⬝ H ⬝ !add.comm,
  add.cancel_left H2

theorem eq_zero_of_add_eq_zero_right {n m : ℕ} : n + m = 0 → n = 0 :=
nat.rec_on n
  (take (H : 0 + m = 0), rfl)
  (take k IH,
    assume H : succ k + m = 0,
    absurd
      (show succ (k + m) = 0, from calc
         succ (k + m) = succ k + m : succ_add
                  ... = 0          : H)
      !succ_ne_zero)

theorem eq_zero_of_add_eq_zero_left {n m : ℕ} (H : n + m = 0) : m = 0 :=
eq_zero_of_add_eq_zero_right (!add.comm ⬝ H)

theorem eq_zero_and_eq_zero_of_add_eq_zero {n m : ℕ} (H : n + m = 0) : n = 0 × m = 0 :=
(eq_zero_of_add_eq_zero_right H, eq_zero_of_add_eq_zero_left H)

theorem add_one (n : ℕ) : n + 1 = succ n :=
!add_zero ▸ !add_succ

theorem one_add (n : ℕ) : 1 + n = succ n :=
!zero_add ▸ !succ_add

/- multiplication -/

theorem mul_zero (n : ℕ) : n * 0 = 0 :=
rfl

theorem mul_succ (n m : ℕ) : n * succ m = n * m + n :=
rfl

-- commutativity, distributivity, associativity, identity

theorem zero_mul (n : ℕ) : 0 * n = 0 :=
nat.rec_on n
  !mul_zero
  (take m IH, !mul_succ ⬝ !add_zero ⬝ IH)

theorem succ_mul (n m : ℕ) : (succ n) * m = (n * m) + m :=
nat.rec_on m
  (!mul_zero ⬝ !mul_zero⁻¹ ⬝ !add_zero⁻¹)
  (take k IH, calc
    succ n * succ k = succ n * k + succ n   : mul_succ
                ... = n * k + k + succ n    : IH
                ... = n * k + (k + succ n)  : add.assoc
                ... = n * k + (succ n + k)  : add.comm
                ... = n * k + (n + succ k)  : succ_add_eq_succ_add
                ... = n * k + n + succ k    : add.assoc
                ... = n * succ k + succ k   : mul_succ)

theorem mul.comm (n m : ℕ) : n * m = m * n :=
nat.rec_on m
  (!mul_zero ⬝ !zero_mul⁻¹)
  (take k IH, calc
    n * succ k = n * k + n    : mul_succ
           ... = k * n + n    : IH
           ... = (succ k) * n : succ_mul)

theorem mul.right_distrib (n m k : ℕ) : (n + m) * k = n * k + m * k :=
nat.rec_on k
  (calc
    (n + m) * 0 = 0             : mul_zero
            ... = 0 + 0         : add_zero
            ... = n * 0 + 0     : mul_zero
            ... = n * 0 + m * 0 : mul_zero)
  (take l IH, calc
    (n + m) * succ l = (n + m) * l + (n + m)    : mul_succ
                 ... = n * l + m * l + (n + m)  : IH
                 ... = n * l + m * l + n + m    : add.assoc
                 ... = n * l + n + m * l + m    : add.right_comm
                 ... = n * l + n + (m * l + m)  : add.assoc
                 ... = n * succ l + (m * l + m) : mul_succ
                 ... = n * succ l + m * succ l  : mul_succ)

theorem mul.left_distrib (n m k : ℕ) : n * (m + k) = n * m + n * k :=
calc
  n * (m + k) = (m + k) * n    : mul.comm
          ... = m * n + k * n  : mul.right_distrib
          ... = n * m + k * n  : mul.comm
          ... = n * m + n * k  : mul.comm

theorem mul.assoc (n m k : ℕ) : (n * m) * k = n * (m * k) :=
nat.rec_on k
  (calc
    (n * m) * 0 = n * (m * 0) : mul_zero)
  (take l IH,
    calc
      (n * m) * succ l = (n * m) * l + n * m : mul_succ
                   ... = n * (m * l) + n * m : IH
                   ... = n * (m * l + m)     : mul.left_distrib
                   ... = n * (m * succ l)    : mul_succ)

theorem mul_one (n : ℕ) : n * 1 = n :=
calc
  n * 1 = n * 0 + n : mul_succ
    ... = 0 + n     : mul_zero
    ... = n         : zero_add

theorem one_mul (n : ℕ) : 1 * n = n :=
calc
  1 * n = n * 1 : mul.comm
    ... = n     : mul_one

theorem eq_zero_or_eq_zero_of_mul_eq_zero {n m : ℕ} : n * m = 0 → n = 0 ⊎ m = 0 :=
nat.cases_on n
  (assume H, sum.inl rfl)
  (take n',
    nat.cases_on m
      (assume H, sum.inr rfl)
      (take m',
        assume H : succ n' * succ m' = 0,
        absurd
          ((calc
            0 = succ n' * succ m' : H
             ... = succ n' * m' + succ n' : mul_succ
             ... = succ (succ n' * m' + n') : add_succ)⁻¹)
          !succ_ne_zero))

end nat