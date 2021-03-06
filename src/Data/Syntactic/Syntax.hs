{-# LANGUAGE OverlappingInstances #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Generic representation of typed syntax trees
--
-- For details, see: A Generic Abstract Syntax Model for Embedded Languages
-- (ICFP 2012, <http://www.cse.chalmers.se/~emax/documents/axelsson2012generic.pdf>).

module Data.Syntactic.Syntax
    ( -- * Syntax trees
      AST (..)
    , ASTF
    , Full (..)
    , (:->) (..)
    , size
    , DenResult
      -- Smart constructors
    , SigRep (..)
    , Signature (..)
    , SmartFun
    , SmartSig
    , SmartSym
    , smartSym'
      -- * Open symbol domains
    , (:+:) (..)
    , Project (..)
    , (:<:) (..)
    , smartSym
    , Empty
      -- * Existential quantification
    , E (..)
    , liftE
    , liftE2
    , EF (..)
    , liftEF
    , liftEF2
      -- * Type inference
    , symType
    , prjP
    ) where



import Data.Foldable (Foldable)
import Data.Traversable (Traversable)
import Data.Typeable

import Data.Proxy



--------------------------------------------------------------------------------
-- * Syntax trees
--------------------------------------------------------------------------------

-- | Generic abstract syntax tree, parameterized by a symbol domain
--
-- @(`AST` sym (a `:->` b))@ represents a partially applied (or unapplied)
-- symbol, missing at least one argument, while @(`AST` sym (`Full` a))@
-- represents a fully applied symbol, i.e. a complete syntax tree.
data AST sym sig
  where
    Sym  :: sym sig -> AST sym sig
    (:$) :: AST sym (a :-> sig) -> AST sym (Full a) -> AST sym sig

infixl 1 :$

-- | Fully applied abstract syntax tree
type ASTF sym a = AST sym (Full a)

instance Functor sym => Functor (AST sym)
  where
    fmap f (Sym s)  = Sym (fmap f s)
    fmap f (s :$ a) = fmap (fmap f) s :$ a

-- | Signature of a fully applied symbol
newtype Full a = Full { result :: a }
  deriving (Eq, Show, Typeable, Functor)

-- | Signature of a partially applied (or unapplied) symbol
newtype a :-> sig = Partial (a -> sig)
  deriving (Typeable, Functor)

infixr :->

-- | Count the number of symbols in an 'AST'
size :: AST sym sig -> Int
size (Sym _)  = 1
size (s :$ a) = size s + size a

-- | The result type of a symbol with the given signature
type family   DenResult sig
type instance DenResult (Full a)    = a
type instance DenResult (a :-> sig) = DenResult sig



--------------------------------------------------------------------------------
-- * Smart constructors
--------------------------------------------------------------------------------

-- | Witness of the arity of a symbol signature
data SigRep sig
  where
    SigFull :: SigRep (Full a)
    SigMore :: SigRep sig -> SigRep (a :-> sig)

-- | Symbol signatures
class Signature sig
  where
    signature :: SigRep sig

instance Signature (Full a)
  where
    signature = SigFull

instance Signature sig => Signature (a :-> sig)
  where
    signature = SigMore signature

-- | Maps a symbol signature to the type of the corresponding smart constructor:
--
-- > SmartFun sym (a :-> b :-> ... :-> Full x) = ASTF sym a -> ASTF sym b -> ... -> ASTF sym x
type family   SmartFun (sym :: * -> *) sig
type instance SmartFun sym (Full a)    = ASTF sym a
type instance SmartFun sym (a :-> sig) = ASTF sym a -> SmartFun sym sig

-- | Maps a smart constructor type to the corresponding symbol signature:
--
-- > SmartSig (ASTF sym a -> ASTF sym b -> ... -> ASTF sym x) = a :-> b :-> ... :-> Full x
type family   SmartSig f
type instance SmartSig (AST sym sig)     = sig
type instance SmartSig (ASTF sym a -> f) = a :-> SmartSig f

-- | Returns the symbol in the result of a smart constructor
type family   SmartSym f :: * -> *
type instance SmartSym (AST sym sig) = sym
type instance SmartSym (a -> f)      = SmartSym f

-- | Make a smart constructor of a symbol. 'smartSym' has any type of the form:
--
-- > smartSym
-- >     :: sym (a :-> b :-> ... :-> Full x)
-- >     -> (ASTF sym a -> ASTF sym b -> ... -> ASTF sym x)
smartSym' :: forall sig f sym
    .  ( Signature sig
       , f   ~ SmartFun sym sig
       , sig ~ SmartSig f
       , sym ~ SmartSym f
       )
    => sym sig -> f
smartSym' s = go (signature :: SigRep sig) (Sym s)
  where
    go :: forall sig . SigRep sig -> AST sym sig -> SmartFun sym sig
    go SigFull s       = s
    go (SigMore sig) s = \a -> go sig (s :$ a)



--------------------------------------------------------------------------------
-- * Open symbol domains
--------------------------------------------------------------------------------

-- | Direct sum of two symbol domains
data (sym1 :+: sym2) a
  where
    InjL :: sym1 a -> (sym1 :+: sym2) a
    InjR :: sym2 a -> (sym1 :+: sym2) a
  deriving (Functor, Foldable, Traversable)

infixr :+:

-- | Symbol projection
--
-- The class is defined for /all pairs of types/, but 'prj' can only succeed if @sup@ is of the form
-- @(... `:+:` sub `:+:` ...)@.
class Project sub sup
  where
    -- | Partial projection from @sup@ to @sub@
    prj :: sup a -> Maybe (sub a)

instance Project sub sup => Project sub (AST sup)
  where
    prj (Sym s) = prj s
    prj _       = Nothing

instance Project sym sym
  where
    prj = Just

instance Project sym1 (sym1 :+: sym2)
  where
    prj (InjL a) = Just a
    prj _        = Nothing

instance Project sym1 sym3 => Project sym1 (sym2 :+: sym3)
  where
    prj (InjR a) = prj a
    prj _        = Nothing

-- | If @sub@ is not in @sup@, 'prj' always returns 'Nothing'.
instance Project sub sup
  where
    prj _ = Nothing

-- | Symbol injection
--
-- The class includes types @sub@ and @sup@ where @sup@ is of the form @(... `:+:` sub `:+:` ...)@.
class Project sub sup => sub :<: sup
  where
    -- | Injection from @sub@ to @sup@
    inj :: sub a -> sup a

instance (sub :<: sup) => (sub :<: AST sup)
  where
    inj = Sym . inj

instance (sym :<: sym)
  where
    inj = id

instance (sym1 :<: (sym1 :+: sym2))
  where
    inj = InjL

instance (sym1 :<: sym3) => (sym1 :<: (sym2 :+: sym3))
  where
    inj = InjR . inj

-- The reason for separating the `Project` and `(:<:)` classes is that there are
-- types that can be instances of the former but not the latter due to type
-- constraints on the `a` type.

-- | Make a smart constructor of a symbol. 'smartSym' has any type of the form:
--
-- > smartSym :: (sub :<: AST sup)
-- >     => sub (a :-> b :-> ... :-> Full x)
-- >     -> (ASTF sup a -> ASTF sup b -> ... -> ASTF sup x)
smartSym
    :: ( Signature sig
       , f   ~ SmartFun sup sig
       , sig ~ SmartSig f
       , sup ~ SmartSym f
       , sub :<: sup
       )
    => sub sig -> f
smartSym = smartSym' . inj

-- | Empty symbol type
--
-- Can be used to make uninhabited 'AST' types. It can also be used as a terminator in co-product
-- lists (e.g. to avoid overlapping instances):
--
-- > (A :+: B :+: Empty)
data Empty :: * -> *



--------------------------------------------------------------------------------
-- * Existential quantification
--------------------------------------------------------------------------------

-- | Existential quantification
data E e
  where
    E :: e a -> E e

liftE :: (forall a . e a -> b) -> E e -> b
liftE f (E a) = f a

liftE2 :: (forall a b . e a -> e b -> c) -> E e -> E e -> c
liftE2 f (E a) (E b) = f a b

-- | Existential quantification of 'Full'-indexed type
data EF e
  where
    EF :: e (Full a) -> EF e

liftEF :: (forall a . e (Full a) -> b) -> EF e -> b
liftEF f (EF a) = f a

liftEF2 :: (forall a b . e (Full a) -> e (Full b) -> c) -> EF e -> EF e -> c
liftEF2 f (EF a) (EF b) = f a b



--------------------------------------------------------------------------------
-- * Type inference
--------------------------------------------------------------------------------

-- | Constrain a symbol to a specific type
symType :: Proxy sym -> sym sig -> sym sig
symType _ = id

-- | Projection to a specific symbol type
prjP :: Project sub sup => Proxy sub -> sup sig -> Maybe (sub sig)
prjP _ = prj

