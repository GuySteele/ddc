
module Main
exports 
 main
  ::    [r : %]. Nat# -> Ptr# r String# -(Console | $0)> Int#

imports 
 showNat   
  ::    [r : %]. Nat# -> Ptr# r String#

 putStrLn  
  ::    [r : %]. Ptr# r String# -(Console | $0)> Void#
 
 boxNat
  ::    [r : %].
        Nat# -(Alloc r | Use r)>
        Nat r

 unboxNat 
  ::    [r : %].
        Nat r -(Read r | $0)>
        Nat#

 addNat 
  ::    [r1 r2 r3 : %].
        Nat r1 -(!0 | Use r3)>
        Nat r2 -(Read r1 + Read r2 + Alloc r3 | Use r1 + Use r3)>
        Nat r3

 subNat 
  ::    [r1 r2 r3 : %].
        Nat r1 -(!0 | Use r3)>
        Nat r2 -(Read r1 + Read r2 + Alloc r3 | Use r1 + Use r3)>
        Nat r3

with letrec


-- | Construct a list containing a single element.
singleton 
        [r : %] [a : *]
        (x : a)                 { Alloc r | Use r }
        : List r a
 = Cons [r] [a] x (Nil [r] [a] ())
             

-- | Take the length of a list.
length  [r1 r2 : %] [a : *]
        (xx : List r1 a)        { Read r1 + Read r2 + Alloc r2 | Use r1 + Use r2 }
        : Nat r2
 = case xx of
        Nil     
         -> N# [r2] 0#

        Cons x xs       
         -> addNat [:r2 r2 r2:] (N# [r2] 1#)
                (length [:r1 r2:] [a] xs)


-- | Construct a list containing copies of some value.
replicate
        [r1 r2 : %] [a : *]
        (n : Nat r1)            { !0 | Use r1 + Use r2 }
        (x : a)                 { Read r1 + Alloc r2 | Use r1 + Use r2}
        : List r2 a
 = letregion r3 in
   case n of
        N# n2   
         -> case eq# [Nat#] n2 0# of
                True#   -> Nil  [r2] [a] ()
                False#  -> Cons [r2] [a] x 
                                (replicate [:r3 r2 a:]
                                        (subNat [:r1 r3 r3:] n (N# [r3] 1#))
                                        x)

-- | Construct a range of Nat values
enumFromTo
        [r1 r2 : %]
        (n      : Nat r2)       { !0 | Use r1 + Use r2 }
        (max    : Nat r2)       { Read r2 + Alloc r1 + Alloc r2 | Use r1 + Use r2 }
        : List r1 (Nat r2)
 = case n of
    N# n2
     -> case max of
         N# max2 
          -> case ge# [Nat#] n2 max2 of
                True#   -> singleton [r1] [Nat r2] n
                False#  -> Cons [r1] [Nat r2] n
                                (enumFromTo [:r1 r2:]
                                        (addNat [:r2 r2 r2:] n (N# [r2] 1#))
                                        max)


-- | Append two lists.
append  [r1 r2 : %] [a : *]
        (xx : List r1 a)        { !0 | Use r1 + Use r2 }
        (yy : List r2 a)        { Read r1 + Alloc r2 | Use r1 + Use r2 + DeepUse a }
        : List r2 a
 = case xx of
        Nil     
         -> yy

        Cons x xs
         -> Cons [r2] [a] x (append [:r1 r2 a:] xs yy)


-- | Quadratic reverse function, used for testing.
reverse [r1 r2 : %] [a : *]
        (xx : List r1 a)        { Read r1 + Read r2 + Alloc r2 | Use r1 + Use r2 }
        : List r2 a
 = case xx of
        Nil     -> Nil [:r2 a:] ()
        Cons x xs
         -> append [:r2 r2 a:] 
                (reverse   [:r1 r2 a:] xs)
                (singleton [:r2 a:] x)


-- | Print out all Nats in a list
dumpNats
        [r1 r2 : %] 
        (xx : List r1 (Nat r2)) { Read r1 + Read r2 + Console | Use r1 + Use r2 }
        : Unit
 = case xx of
        Nil     -> ()
        Cons x xs
         -> case x of
             N# x2
              -> do  putStrLn [r2] (showNat [r2] x2)
                     dumpNats [:r1 r2:] xs


-- | Construct a list of length 23 then take its length.
main    [r : %] 
        (argc : Nat#)
        (argv : Ptr# r String#) { Console | $0 }
        : Int#
 = letregion r2 in
   do
        xs1     = replicate  [:r2 r2:] [Nat r2] (N# [r2] 5#) (N# [r2] 100#)
        xs2     = enumFromTo [:r2 r2:] (N# [r2] 10#) (N# [r2] 20#)

        zs      = append     [:r2 r2:] [Nat r2] xs1 xs2
        zs2     = reverse    [:r2 r2:] [Nat r2] zs

        dumpNats [:r2 r2:] zs2
        0i#

