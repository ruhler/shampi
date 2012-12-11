
{-# LANGUAGE TemplateHaskell #-}

import System.Environment
import Control.Monad.State

import qualified Data.Map as Map
import Data.Maybe (fromJust)
import Data.Functor ((<$>))

import Seri.Type
import Seri.Exp
import Seri.ExpH
import qualified Seri.HaskellF.Symbolic as S
import Seri.HaskellF.Query
import Seri.SMT.Query
import Seri.SMT.Yices.Yices2
import qualified Seri.HaskellF.Lib.Prelude as S
import qualified SeriGen as S

import RegEx
import Hampi
import Grammar

derive_SeriT ''RegEx
derive_SeriEH ''RegEx

type S_Elem = S.Integer
type S_String = S.List__ S_Elem

freevar :: Integer -> Query S_String
freevar = qS . S.frees . S.seriS

-- Make a hampi assertion.
hassert :: Map.Map ID S_String -> Map.Map ID (RegEx Elem) -> Assertion -> Query ()
hassert vals regs (Assert v b r) =
    let vstr = fromJust $ Map.lookup v vals
        rreg = S.seriS . fromJust $ Map.lookup r regs
        positive = S.match rreg vstr
        p = if b then positive else S.not positive
    in assertS p

-- inlinevals varid varval vals
--  Given the var id, it's symbolic value, and the rest of the values, return
--  a mapping from id to totally inlined values.
inlinevals :: ID -> S_String -> Map.Map ID Val -> Map.Map ID S_String
inlinevals varid varval m =
  let lookupval :: Val -> Maybe S_String
      lookupval (ValID x)
        | x == varid = return varval
        | otherwise = Map.lookup x m >>= lookupval
      lookupval (ValLit x) = return $ S.seriS x
      lookupval (ValCat a b) = do
            a' <- lookupval a
            b' <- lookupval b
            return $ a' S.++ b'
      vals = [(id, fromJust $ lookupval v) | (id, v) <- Map.toList m]
  in Map.fromList $ (varid, varval) : vals

-- A hampi query.
hquery :: Hampi -> Query String
hquery (Hampi (Var vid vwidth) vals regs asserts) = do
    svar <- freevar vwidth
    let svals = inlinevals vid svar vals
    mapM_ (hassert svals regs) asserts
    r <- query $ realizeS svar
    case r of
        Satisfiable v ->
          let tostr :: [Elem] -> String
              tostr = map toChar
          in return $ "{VAR(" ++ vid ++ ")=" ++ tostr v ++ "}"
        Unsatisfiable -> return "UNSAT"
        _ -> return "UNKNOWN"


abstar :: RegEx Integer
abstar = starR (stringR "ab")

htest :: Hampi
htest = Hampi {
    h_var = Var "str" 6,
    h_vals = Map.empty,
    h_regs = Map.singleton "abstar" abstar,
    h_asserts = [Assert "str" True "abstar"]
}

main :: IO ()
main = do
    args <- getArgs
    fin <- case args of
             f:_ -> return f
             _ -> fail "Usage: Hampi <filename> [timeout in secs]"
    input <- readFile fin
    h <- case runStateT parseHampi input of
            Left msg -> fail msg
            Right x -> return $ fst x
    y <- yices2
    r <- runQuery (RunOptions (Just "hampi.dbg") y) (hquery h)
    putStrLn r

