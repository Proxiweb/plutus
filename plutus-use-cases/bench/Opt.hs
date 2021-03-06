{-# LANGUAGE LambdaCase #-}
-- We don't normally do this to avoid being sensitive to GHC's optimzations,
-- but here we're precisely testing how much difference that makes.
{-# OPTIONS_GHC -fexpose-all-unfoldings #-}
{-# OPTIONS_GHC -O2 #-}
{-# OPTIONS_GHC -fno-strictness #-}
module Opt where

import           Prelude                   hiding (tail)

import qualified Language.PlutusTx.Prelude as P

{-# ANN module "HLint: ignore" #-}

fibOpt :: Integer -> Integer
fibOpt n =
    if n P.== 0
    then 0
    else if n P.== 1
    then 1
    else fibOpt (n `P.minus` 1) `P.plus` fibOpt (n `P.minus` 2)

fromToOpt :: Integer -> Integer -> [Integer]
fromToOpt f t =
    if f P.== t then [f]
    else f:(fromToOpt (f `P.plus` 1) t)

foldrOpt :: (a -> b -> b) -> b -> [a] -> b
foldrOpt f z = go
    where go []    = z
          go (h:t) = h `f` go t

tailOpt :: [a] -> Maybe a
tailOpt = \case
    [] -> Nothing
    (x:[]) -> Just x
    (_:xs) -> tailOpt xs
