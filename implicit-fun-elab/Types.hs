
module Types (
  module Types,
  module Text.Megaparsec
  ) where

import Control.Exception
import Text.Megaparsec (SourcePos(..), unPos, initialPos)
import Text.Printf
import Lens.Micro.Platform

import qualified Data.IntMap.Strict as IM
import qualified Data.IntSet        as IS

-- Raw syntax
--------------------------------------------------------------------------------

newtype SPos = SPos SourcePos deriving (Eq, Ord, Read)
instance Show SPos where show _ = ""

type Name = String
data Icit = Impl | Expl deriving (Eq)

instance Show Icit where
  show Expl = "explicit"
  show Impl = "implicit"

icit :: Icit -> a -> a -> a
icit Impl i e = i
icit Expl i e = e

data Raw
  = RVar Name
  | RLam Name (Maybe Raw) Icit Raw
  | RApp Raw Raw Icit
  | RU
  | RPi Name Icit Raw Raw
  | RLet Name Raw Raw Raw
  | RHole
  | RSrcPos SPos Raw

deriving instance Show Raw


-- Types
--------------------------------------------------------------------------------

-- | Elaboration problem identifier.
type MId = Int

-- | Blocked problems.
type Blocking  = IS.IntSet
type BlockedBy = IS.IntSet

data MetaEntry
  = Unsolved Blocking ~VTy
  | Solved Val

  -- | Telescope constancy constraint. When the closure becomes constant,
  --   we unify the telescope with the empty telescope.
  | Constancy MId Spine Name Val BlockedBy

data Vals  = VNil | VDef Vals ~Val | VSkip Vals
data Types = TNil | TDef Types ~VTy | TBound Types ~VTy
type Ix    = Int
type Lvl   = Int
type Ty    = Tm
type VTy   = Val
type MCxt  = IM.IntMap MetaEntry

pattern TSnoc :: Types -> VTy -> Types
pattern TSnoc as a <- ((\case TBound as a -> Just (as, a)
                              TDef as a   -> Just (as, a)
                              TNil        -> Nothing) -> Just (as, a))

lvlName :: [Name] -> Lvl -> Name
lvlName ns x = ns !! (length ns - x - 1)

-- -- clean these up
-- typesLen :: Types -> Int
-- typesLen = go 0 where
--   go acc TNil           = acc
--   go acc (TDef tys _)   = go (acc + 1) tys
--   go acc (TBound tys _) = go (acc + 1) tys

ixType :: Types -> Ix -> VTy
ixType TNil           _ = error "impossible"
ixType (TDef   tys a) 0 = a
ixType (TBound tys a) 0 = a
ixType (TDef   tys a) x = ixType tys (x - 1)
ixType (TBound tys a) x = ixType tys (x - 1)

-- lvlType :: Types -> Lvl -> VTy
-- lvlType tys x = ixType tys (typesLen tys - x - 1)

data NameOrigin = NOSource | NOInserted

data Cxt = Cxt {
  cxtVals       :: Vals,
  cxtTypes      :: Types,
  cxtNames      :: [Name],
  cxtNameOrigin :: [NameOrigin],
  cxtLen        :: Int}

data UnifyCxt = UCxt {
  unifyCxtTypes :: Types,
  unifyCxtNames :: [Name],
  unifyCxtLen   :: Int }

data Err = Err {
  errNames :: [Name],
  errErr   :: ElabError,
  errPos   :: Maybe SPos}

data Tm
  = Var Ix
  | Let Name Ty Tm Tm

  | Pi Name Icit Ty Ty
  | Lam Name Icit Ty Tm
  | App Tm Tm Icit

  | Tel               -- Ty Γ
  | TEmpty            -- Tm Γ Tel
  | TCons Name Ty Ty  -- (A : Ty Γ) → Tm (Γ ▶ A) Tel → Tm Γ Tel
  | Rec Tm            -- Tm Γ Tel → Ty Γ

  | Tempty            -- Tm Γ (El TEmpty)
  | Tcons Tm Tm       -- (t : Tm Γ A) → Tm Γ (Δ[id, t]) → Tm Γ (El (TCons A Δ))
  | Proj1 Tm          -- Tm Γ (El (TCons A Δ)) → Tm Γ A
  | Proj2 Tm          -- (t : Tm Γ (El (TCons A Δ))) → Tm Γ (El (Δ[id, Proj₁ t]))

  | PiTel Name Ty Ty  -- (A : Tm Γ Tel) → Ty (Γ ▶ El A) → Ty Γ
  | AppTel Ty Tm Tm   -- (A : Tm Γ Tel)(t : Tm Γ (PiTel A B))(u : Tm Γ A)
                      -- → Tm Γ B[id, u]
  | LamTel Name Ty Tm -- (A : Tm Γ Tel)(t : Tm (Γ ▶ El A) B) → Tm Γ (PiTel A B)

  | U
  | Meta MId

data Spine
  = SNil
  | SApp Spine ~Val Icit
  | SAppTel ~Val Spine ~Val
  | SProj1 Spine
  | SProj2 Spine

valsLen :: Vals -> Int
valsLen = go 0 where
  go acc VNil        = acc
  go acc (VDef vs _) = go (acc + 1) vs
  go acc (VSkip vs)  = go (acc + 1) vs

-- spLen :: Spine -> Int
-- spLen = go 0 where
--   go n SNil             = n
--   go n (SApp sp _ _)    = go (n + 1) sp
--   go n (SAppTel _ sp _) = go (n + 1) sp
--   go n (SProj1 sp)      = go (n + 1) sp
--   go n (SProj2 sp)      = go (n + 1) sp

data Head
  = HVar Lvl
  | HMeta MId
  deriving (Eq, Show)

data Val
  = VNe Head Spine

  | VPi Name Icit ~VTy (VTy -> VTy)
  | VLam Name Icit ~VTy (Val -> Val)
  | VU

  | VTel
  | VRec ~Val
  | VTEmpty
  | VTCons Name ~Val (Val -> Val)
  | VTempty
  | VTcons ~Val ~Val

  | VPiTel Name ~Val (Val -> Val)
  | VLamTel Name ~Val (Val -> Val)

type MetaInsertion = Bool

pattern VVar :: Lvl -> Val
pattern VVar x = VNe (HVar x) SNil

pattern VMeta :: MId -> Val
pattern VMeta m = VNe (HMeta m) SNil

data ElabError
  = SpineNonVar Tm Tm                    -- ^ lhs, rhs
  | SpineProjection
  | ScopeError Tm Tm Lvl                 -- ^ Lhs, rhs, offending variable
  | OccursCheck Tm Tm                    -- ^ Lhs, rhs
  | UnifyError Tm Tm                     -- ^ Lhs, rhs
  | UnifyErrorWhile Tm Tm Tm Tm
  | NameNotInScope Name
  | ExpectedFunction Tm                  -- ^ Inferred type.
  | IcitMismatch Icit Icit
  | NonLinearSolution Tm Tm Lvl          -- ^ Lhs, rhs, offending variable

instance Show Err where
  show _ = "Error"

instance Exception Err

report :: [Name] -> ElabError -> a
report ns e = throw (Err ns e Nothing)

-- Pretty printing
--------------------------------------------------------------------------------

-- | Assumption: the `[Name]` input does not have shadowing.
prettyTm :: Int -> [Name] -> Tm -> ShowS
prettyTm prec = go (prec /= 0) where

  fresh :: [Name] -> Name -> Name
  fresh _ "_" = "_"
  fresh ns n | elem n ns = fresh ns (n++"'")
             | otherwise = n

  goVar :: [Name] -> Ix -> ShowS
  -- goVar ns topX = (show topX++)
  goVar ns topX = go ns topX where
    go []     _ = error "impossible"
    go (n:ns) 0 = (n++)
    go (n:ns) x = go ns (x - 1)

  goArg :: [Name] -> Tm -> Icit -> ShowS
  goArg ns t i = icit i (bracket (go False ns t)) (go True ns t)

  goLamBind :: Name -> Icit -> ShowS
  goLamBind x i = icit i bracket id ((if null x then "_" else x) ++)

  bracket :: ShowS -> ShowS
  bracket s = ('{':).s.('}':)

  goLam :: [Name] -> Tm -> ShowS
  goLam ns (Lam (fresh ns -> x) i a t)  = (' ':) . goLamBind x i . goLam (x:ns) t
  goLam ns (LamTel(fresh ns -> x) a t) =
    (' ':) . bracket ((x++) . (" : "++) . go False ns a) . goLam (x:ns) t
  goLam ns t = (". "++) . go False ns t

  goPiBind :: [Name] -> Name -> Icit -> Tm -> ShowS
  goPiBind ns x i a =
    icit i bracket (showParen True) ((x++) . (" : "++) . go False ns a)

  goPi :: [Name] -> Bool -> Tm -> ShowS
  goPi ns p (Pi (fresh ns -> x) i a b)
    | x /= "_" = goPiBind ns x i a . goPi (x:ns) True b
    | otherwise =
       (if p then (" → "++) else id) .
       go (case a of App{} -> False; AppTel{} -> False; _ -> True) ns a .
       (" → "++) . go False (x:ns) b

  goPi ns p (PiTel (fresh ns -> x) a b)
    | x /= "_" = goPiBind ns x Impl a . goPi (x:ns) True b
    | otherwise =
       (if p then (" → "++) else id) .
       go (case a of App{} -> False; AppTel{} -> False; _ -> True) ns a .
       (" → "++) . go False (x:ns) b

  goPi ns p t = (if p then (" → "++) else id) . go False ns t

  go :: Bool -> [Name] -> Tm -> ShowS
  go p ns = \case
    Var x -> goVar ns x
    Meta m -> ("?"++).(show m++)
    Let (fresh ns -> x) a t u ->
      ("let "++) . (x++) . (" : "++) . go False ns a . ("\n    = "++)
      . go False ns t  . ("\nin\n"++) . go False (x:ns) u
    App (App t u i) u' i' ->
      showParen p (go False ns t . (' ':) . goArg ns u i . (' ':) . goArg ns  u' i')
    App (AppTel _ t u) u' i' ->
      showParen p (go False ns t . (' ':) . goArg ns u Impl . (' ':) . goArg ns u' i')
    App t u i      -> showParen p (go True ns t . (' ':) . goArg ns u i)
    Lam (fresh ns -> x) i a t  -> showParen p (("λ "++) . goLamBind x i . goLam (x:ns) t)
    t@Pi{}         -> showParen p (goPi ns False t)
    U              -> ("U"++)
    Tel            -> ("Tel"++)
    TEmpty         -> ("∙"++)
    TCons "_" a as -> showParen p (go False ns a . (" ▶ "++). go False ns as)
    TCons (fresh ns -> x) a as ->
              showParen p (showParen True ((x++) . (" : "++) . go False ns a)
            . (" ▶ "++). go False (x:ns) as)
    Tempty         -> ("[]"++)
    Rec a          -> showParen p (("Rec "++) . go True ns a)
    Tcons t u      -> showParen p (go True ns t . (" ∷ "++). go False ns u)
    Proj1 t        -> showParen p (("₁ "++). go True ns t)
    Proj2 t        -> showParen p (("₂ "++). go True ns t)
    t@PiTel{}      -> showParen p (goPi ns False t)
    AppTel a (App t u i) u'  ->
      showParen p (go False ns t . (' ':) . goArg ns u i . (' ':) .
                   bracket (go False ns u' . (" : "++) . go False ns a))

    AppTel a' (AppTel a t u) u' ->
      showParen p (go False ns t . (' ':)
                   . bracket (go False ns u  . (" : "++) . go False ns a)
                   . bracket (go False ns u' . (" : "++) . go False ns a'))
    AppTel a t u ->
      showParen p (go True ns t . (' ':)
                   . bracket (go False ns u  . (" : "++) . go False ns a))
    LamTel x a t -> showParen p (("λ"++)
                   . bracket ((x++) . (" : "++) . go False ns a) . goLam ns t)

showTm :: [Name] -> Tm -> String
showTm ns t = prettyTm 0 ns t []
-- showTm ns t = show t

-- deriving instance Show Tm
instance Show Tm where show = showTm []

showError :: [Name] -> ElabError -> String
showError ns = \case
  SpineNonVar lhs rhs -> printf (
    "Non-bound-variable value in meta spine in equation:\n\n" ++
    "  %s =? %s")
    (showTm ns lhs) (showTm ns rhs)
  SpineProjection -> "Projection in meta spine"
  ScopeError lhs rhs x -> printf (
    "Variable %s is out of scope in equation\n\n" ++
    "  %s =? %s")
    (lvlName ns x) (showTm ns lhs) (showTm ns rhs)
  OccursCheck lhs rhs -> printf (
    "Meta occurs cyclically in its solution candidate in equation:\n\n" ++
    "  %s =? %s")
    (showTm ns lhs) (showTm ns rhs)
  UnifyError lhs rhs -> printf
    ("Cannot unify\n\n" ++
     "  %s\n\n" ++
     "with\n\n" ++
     "  %s")
    (showTm ns lhs) (showTm ns rhs)
  UnifyErrorWhile lhs rhs lhs' rhs' -> printf
    ("Cannot unify\n\n" ++
     "  %s\n\n" ++
     "with\n\n" ++
     "  %s\n\n" ++
     "while trying to unify\n\n" ++
     "  %s\n\n" ++
     "with\n\n" ++
     "  %s")
    (showTm ns lhs') (showTm ns rhs') (showTm ns lhs) (showTm ns rhs)
  NameNotInScope x ->
    "Name not in scope: " ++ x
  ExpectedFunction ty ->
    "Expected a function type, instead inferred:\n\n  " ++ showTm ns ty
  IcitMismatch i i' -> printf (
    "Function icitness mismatch: expected %s, got %s.")
    (show i) (show i')
  NonLinearSolution lhs rhs x -> printf
    ("Nonlinear variable %s in meta spine in equation\n\n" ++
     "  %s =? %s")
    (lvlName ns x)
    (showTm ns lhs) (showTm ns rhs)

-- Lenses
--------------------------------------------------------------------------------

makeFields ''Cxt
makeFields ''UnifyCxt
makeFields ''Err

ucxt :: Lens' Cxt UnifyCxt
ucxt f (Cxt vs tys ns no d) =
  (\(UCxt tys ns d) -> Cxt vs tys ns no d) <$> f (UCxt tys ns d)

instance HasNames  [Name]  [Name]  where names = id
instance HasVals   Vals    Vals    where vals  = id
instance HasTypes  Types   Types   where types = id
instance HasLen    Int     Int     where len   = id
