import data.vector
open nat vector

example (a b : nat) : succ a = succ b → a + 2 = b + 2 :=
begin
  intro H,
  injection H with aeqb,
  rewrite aeqb
end

example (A : Type) (n : nat) (v w : vector A n) (a : A) (b : A) :
        a :: v = a :: w →  b :: v = b :: w :=
begin
  intro H, injection H with veqw,
  rewrite veqw
end

example (A : Type) (n : nat) (v w : vector A n) (a : A) (b : A) :
        a :: v = b :: w →  b :: v = a :: w :=
begin
  intro H, injection H with aeqb veqw,
  rewrite [aeqb, veqw]
end

example (A : Type) (a₁ a₂ a₃ b₁ b₂ b₃ : A) : (a₁, a₂, a₃) = (b₁, b₂, b₃) → b₁ = a₁ :=
begin
  intro H, injection H with H₁, injection H₁ with a₁b₁,
  rewrite a₁b₁
end