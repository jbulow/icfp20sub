
module EvalCxt
  (eval, force, quote, Eval.forceU, Eval.vProj1, Eval.vProj2, Eval.vApp, vEq)
  where

import Lens.Micro.Platform

import Types
import qualified Evaluation as Eval

eval :: Cxt -> Tm -> Val
eval cxt = Eval.eval (cxt^.vals) (cxt^.len)

force :: Cxt -> Val -> Val
force cxt = Eval.force (cxt^.len)

quote :: Cxt -> Val -> Tm
quote cxt = Eval.quote (cxt^.len)

vEq :: Cxt -> Val -> Val -> Val -> Val
vEq cxt = Eval.vEq (cxt^.len)