
Require Export DDC.Language.SystemF2.TyBase.


(*******************************************************************)
(* Lift type indices that are at least a certain depth. *)
Fixpoint liftTT (n: nat) (d: nat) (tt: ty) : ty :=
  match tt with
  |  TVar ix
  => if le_gt_dec d ix
      then TVar (ix + n)
      else tt

  |  TCon _     => tt

  |  TForall t 
  => TForall (liftTT n (S d) t)

  |  TApp t1 t2
  => TApp    (liftTT n d t1) (liftTT n d t2)
  end.
Hint Unfold liftTT.


(* Tactic to help deal with lifting functions *)
Ltac lift_cases 
 := match goal with 
     |  [ |- context [le_gt_dec ?n ?n'] ]
     => case (le_gt_dec n n')
    end.


(********************************************************************)
Lemma getCtorOfType_liftTT
 :  forall d ix t 
 ,  getCtorOfType (liftTT d ix t) = getCtorOfType t.
Proof.
 intros.
 induction t; try burn.

 Case "TVar".
  simpl. lift_cases; auto.
Qed.  


Lemma liftTT_takeTCon
 :  forall tt d ix
 ,  liftTT d ix (takeTCon tt) = takeTCon (liftTT d ix tt).
Proof.
 intros.
 induction tt; intros; auto.
 simpl. lift_cases; auto.
Qed.


Lemma liftTT_takeTArgs
 : forall tt d ix
 , map (liftTT d ix) (takeTArgs tt) = takeTArgs (liftTT d ix tt).
Proof.
 intros.
 induction tt; intros; auto.
 simpl. lift_cases; auto.
 simpl. rewrite map_snoc. 
  f_equal. auto.
Qed. 


Lemma liftTT_makeTApps 
 :  forall n d t1 ts
 ,  liftTT n d (makeTApps t1 ts)
 =  makeTApps (liftTT n d t1) (map (liftTT n d) ts). 
Proof.
 intros. gen t1.
 induction ts; intros.
  auto.
  simpl. rewrite IHts. auto.
Qed.


(********************************************************************)
Lemma liftTT_zero
 :  forall d t
 ,  liftTT 0 d t = t.
Proof.
 intros. gen d.
 induction t; intros; eauto.

 Case "TVar".
  simpl. lift_cases; nnat; auto.

 Case "TForall".
   simpl. rewrite IHt. auto.

 Case "TApp".
   simpl. rewrite IHt1. rewrite IHt2. auto.
Qed.


Lemma liftTT_comm
 :  forall n m d t
 ,  liftTT n d (liftTT m d t)
 =  liftTT m d (liftTT n d t).
Proof.
 intros. gen d.
 induction t; intros; eauto.
 
 Case "TVar".
  repeat (simpl; lift_cases; intros); burn.

 Case "TForall".
  simpl. rewrite IHt. auto.

 Case "TApp".
  simpl. rewrite IHt1. rewrite IHt2. auto.
Qed.


Lemma liftTT_succ
 :  forall n m d t
 ,  liftTT (S n) d (liftTT m     d t)
 =  liftTT n     d (liftTT (S m) d t).
Proof.
 intros. gen d m n.
 induction t; intros; eauto.
 
 Case "TVar".
  repeat (simpl; lift_cases; intros); burn.

 Case "TForall".
  simpl. rewrite IHt. auto.

 Case "TApp".
  simpl. rewrite IHt1. rewrite IHt2. auto.
Qed.


Lemma liftTT_plus
 : forall n m d t
 , liftTT n d (liftTT m d t) = liftTT (n + m) d t.
Proof.
 intros. gen n d.
 induction m; intros.
 
 rewrite liftTT_zero. nnat. auto.
 assert (n + S m = S n + m).
  omega. rewrite H. clear H.
 rewrite liftTT_comm.
 rewrite <- IHm.
 rewrite liftTT_comm.
 rewrite liftTT_succ.
 auto.
Qed. 


(* Changing the order of lifting. *)
Lemma liftTT_liftTT'
 :  forall d d' t
 ,  liftTT 1 d              (liftTT 1 (d + d') t) 
 =  liftTT 1 (1 + (d + d')) (liftTT 1 d t).
Proof.
 intros. gen d d'.
 induction t; intros; simpl; try burn.

 Case "TVar".
  repeat (unfold liftTT; lift_cases; intros); burn.

 Case "TForall".
  assert (S (d + d') = (S d) + d'). omega. rewrite H. 
  rewrite IHt. auto.
Qed.  


Lemma liftTT_liftTT''
 :  forall n1 m1 n2 t
 ,  liftTT m1   n1 (liftTT 1 (n2 + n1) t)
 =  liftTT 1 (m1 + n2 + n1) (liftTT m1 n1 t).
Proof.
 intros. gen n1 m1 n2 t.
 induction m1; intros.
  simpl.
   rewrite liftTT_zero.
   rewrite liftTT_zero.
   auto.
  simpl.

  assert (S m1 = 1 + m1). 
   omega. rewrite H.
  
  rewrite <- liftTT_plus.
  rewrite IHm1.
  assert (m1 + n2 + n1 = n1 + (m1 + n2)).
   omega. rewrite H0. clear H0.

  rewrite liftTT_liftTT'.
   simpl. 

   f_equal.
   rewrite liftTT_plus. auto.
Qed.


Lemma liftTT_liftTT
 :  forall m1 n1 m2 n2 t
 ,  liftTT m1 n1 (liftTT m2 (n2 + n1) t)
 =  liftTT m2 (m1 + n2 + n1) (liftTT m1 n1 t).
Proof.
 intros. gen n1 m1 n2 t.
 induction m2; intros.
  rewrite liftTT_zero.
  rewrite liftTT_zero.
  auto.
  
  assert (S m2 = 1 + m2).
   omega. rewrite H.
  
  rewrite <- liftTT_plus.
  rewrite liftTT_liftTT''.
  rewrite IHm2.
  rewrite -> liftTT_plus. auto.
Qed.
  