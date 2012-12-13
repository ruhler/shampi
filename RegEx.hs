module RegEx where

import qualified Data.Map as Map

import Debug.Trace
import SeriRegEx

instance (Show c) => Show (RegEx c) where
    show (Epsilon) = "Epsilon"
    show (Empty)   = "Empty"    
    show (Atom c)  = "Atom " ++ show c
    show (Range cmin cmax) = "Range " ++ show cmin ++ " " ++ show cmax
    show (Star x)      = "Star (" ++ show x ++ ")"
    show (Concat a b)  = "Concat (" ++ show a ++ ") (" ++ show b ++ ")"
    show (Or a b)      = "Or (" ++ show a ++ ") (" ++ show b ++ ")"
    show (Variable id) = "Variable " ++ show id
    show (Fix f n)     = "Fix (" ++ show f ++ ") " ++ show n
                         
charR :: (FromChar c) => Char -> RegEx c
charR c = Atom (fromChar c)

concatR :: RegEx c -> RegEx c -> RegEx c
concatR Empty          y = Empty
concatR Epsilon        y = y            
concatR (Concat x1 x2) y = x1 `concatR` (x2 `concatR` y )            
concatR x          Empty = Empty
concatR x        Epsilon = x
concatR x              y = Concat x y

concatsR :: [RegEx c] -> RegEx c
concatsR = foldl concatR epsilonR

orsR :: [RegEx c] -> RegEx c
orsR = foldl orR emptyR

orR :: RegEx c -> RegEx c -> RegEx c
orR Empty      y = y
orR (Or x1 x2) y = x1 `orR` (x2 `orR` y)           
orR x      Empty = x
orR x          y = Or x y                                    

epsilonR :: RegEx c
epsilonR = Epsilon

varR :: ID -> RegEx c
varR = Variable

fixR :: RegEx c -> Integer -> RegEx c
fixR = Fix

stringR :: (FromChar c) => String -> RegEx c
stringR str = foldr concatR Epsilon (map charR str)

starR :: RegEx c -> RegEx c
starR Epsilon = Epsilon
starR Empty   = Empty  
starR x       = Star x

plusR :: RegEx c -> RegEx c
plusR r = concatR r (starR r)

optionR :: RegEx c -> RegEx c
optionR r = orR epsilonR r

rangeR :: (FromChar c) => Char -> Char -> RegEx c
rangeR a b = Range (fromChar a) (fromChar b)

emptyR :: RegEx c
emptyR = Empty

-------------------------------------------------

matchEpsilon :: Map.Map ID (RegEx c) -> RegEx c -> Bool
matchEpsilon env          Empty = False
matchEpsilon env        Epsilon = True
matchEpsilon env       (Atom _) = False
matchEpsilon env     (Range {}) = False
matchEpsilon env       (Star _) = True
matchEpsilon env (Concat c1 c2) = matchEpsilon env c1 && matchEpsilon env c2
matchEpsilon env     (Or c1 c2) = matchEpsilon env c1 || matchEpsilon env c2
matchEpsilon env   (Variable i) = case Map.lookup i env of
                                    Nothing  -> False
                                    (Just c) -> matchEpsilon (Map.filterWithKey (\x _ -> x /= i) env) c -- okay for match epsilon
matchEpsilon env      (Fix r n) = n == 0 && matchEpsilon env r

fixNonZero :: Map.Map ID (RegEx c) -> RegEx c -> RegEx c
fixNonZero env c | not (matchEpsilon env c) = c
fixNonZero env Empty            = Empty
fixNonZero env Epsilon          = Empty
fixNonZero env c@(Atom {})      = c
fixNonZero env c@(Range {})     = c
fixNonZero env c@(Star cb)      = concatR (fixNonZero env cb) c
fixNonZero env c@(Concat c1 c2) = case (matchEpsilon env c1, matchEpsilon env c2) of
                                      (True, True) -> orsR [fixNonZero env c1, fixNonZero env c2,
                                                            concatR (fixNonZero env c1) (fixNonZero env c2)]
                                      _            -> c
fixNonZero env c@(Or c1 c2)     = Or (fixNonZero env c1) (fixNonZero env c2)
fixNonZero env (Variable i)          = case Map.lookup i env of
                                      Nothing  -> Empty
                                      (Just c) -> fixNonZero env c
fixNonZero env c@(Fix _ i)        = if i == 0 then Empty else c

fixTable :: (Show c) => Map.Map ID (RegEx c) -> Integer -> Map.Map Integer (Map.Map ID (RegEx c))
fixTable env sz = table
  where table = Map.mapWithKey (\n idmap -> Map.mapWithKey (\i r -> inline (n,i) r) idmap) fixtable
        --inline key c | trace ("\n\nINLINE: " ++  show key ++ " => " ++ show c) False = error ""
        inline key (Star cb)           = Star (inline key cb)
        inline key (Concat c1 c2)      = concatR (inline key c1) (inline key c2)
        inline key (Or c1 c2)          = orR (inline key c1) (inline key c2)
        inline key@(n,i) (Variable i') = case Map.lookup n table of
                                           Just m | i /= i', (Just r) <- Map.lookup i' m -> r
                                           _                                             -> Empty
        inline key@(n,i) (Fix r n')    = if n == n' then inline key r else Empty
        inline key r                   = r                                      
        fixtable = (Map.fromList [(n, Map.map (\c -> fix' n n c) env) | n <- [0..sz]])
        fix' n0 0 cfg         = if matchEpsilon env cfg then Epsilon else Empty       
        fix' n0 n Empty       = Empty
        fix' n0 n Epsilon     = if n == 0 then Epsilon else Empty 
        fix' n0 n c@(Atom {}) = if n == 1 then c else Empty
        fix' n0 n c@(Range{}) = if n == 1 then c else Empty        
        fix' n0 n c@(Star cb) = if n == 0 then Epsilon else fix' n0 n (concatR (fixNonZero env cb) c)
        --fix' n0 n c@(Star cb) = if n == 0 then Epsilon else fix' n0 n (concatR cb c)
        fix' n0 n c@(Concat c1 c2) = orsR $ map (\x -> concatR (fix' n0 x c1) (fix' n0 (n-x) c2)) [0..n]
        fix' n0 n (Or c1 c2)       = orR (fix' n0 n c1) (fix' n0 n c2)        
        fix' n0 n c@(Variable i) = case Map.lookup n fixtable of
                                          Just m | n0 /= n, (Just r) <- Map.lookup i m -> r
                                          _                                              -> Fix c n
        fix' n0 n (Fix c n')      = if n /= n' then Empty else fix' n0 n c        

