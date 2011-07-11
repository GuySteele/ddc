
Require Import DDC.Language.SimpleData.Step.
Require Import DDC.Language.SimpleData.TyJudge.
Require Import DDC.Language.SimpleData.SubstExpExp.
 

(* When a well typed expression transitions to the next state
   then its type is preserved. *)
Theorem preservation
 :  forall ds x x' t
 ,  TYPE ds nil x  t
 -> STEP x x'
 -> TYPE ds nil x' t.
Proof.
 intros ds x x' t HT HS. gen t.
 induction HS; intros.

 (* Evaluation in an arbitrary context. *)
 Case "EsContext".
  destruct H; eauto; 
   try (inverts HT; progress eauto).

  SCase "XCon".
   inverts HT.
   eapply TYCon; eauto.
   eapply context_Forall2_swap; eauto.

 Case "EsLamApp".
  inverts HT. inverts H4.
  eapply subst_exp_exp; eauto.

 Case "EsCaseAlt".
  inverts keep HT. inverts H3.
  eapply subst_exp_exp_list.
  eauto. 
  eapply getAlt_inAlts; eauto.
   eauto.

  assert (tsArgs = tsArgs0).
   lets D: getAlt_matches_dataDef H4 H7 H0. auto.
   rewrite <- H1. clear H1.
  auto.
Qed.


(* When we multi-step evaluate some expression,
   then the result has the same type as the original. *)  
Lemma preservation_steps
 :  forall ds x1 t1 x2
 ,  TYPE ds nil x1 t1
 -> STEPS       x1 x2
 -> TYPE ds nil x2 t1.
Proof.
 intros. 
 induction H0; eauto.
  eapply preservation; eauto.
Qed.


(* When we multi-step evaluate some expression, 
   then the result has the same type as the original.
   Using the left-linearised form for the evaluation.
 *)
Lemma preservation_stepsl
 :  forall ds x1 t1 x2
 ,  TYPE ds nil x1 t1
 -> STEPSL x1 x2
 -> TYPE ds nil x2 t1.
Proof.
 intros. 
 induction H0.
  auto.
  apply IHSTEPSL.
  eapply preservation. 
   eauto. auto.
Qed.
