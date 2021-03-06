-- | A guessing game
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# OPTIONS_GHC -fno-ignore-interface-pragmas #-}
module Language.PlutusTx.Coordination.Contracts.Game(
    lock,
    guess,
    startGame,
    -- * Scripts
    gameValidator,
    gameDataScript,
    gameRedeemerScript,
    -- * Address
    gameAddress,
    validateGuess
    ) where

import qualified Language.PlutusTx            as PlutusTx
import           Language.PlutusTx.Prelude
import           Ledger
import           Ledger.Value                 (Value)
import           Wallet

import qualified Data.ByteString.Lazy.Char8   as C

data HashedString = HashedString ByteString

PlutusTx.makeLift ''HashedString

data ClearString = ClearString ByteString

PlutusTx.makeLift ''ClearString

correctGuess :: HashedString -> ClearString -> Bool
correctGuess (HashedString actual) (ClearString guess') = actual == (sha2_256 guess')

validateGuess :: HashedString -> ClearString -> PendingTx -> Bool
validateGuess dataScript redeemerScript _ = correctGuess dataScript redeemerScript

gameValidator :: ValidatorScript
gameValidator =
    ValidatorScript ($$(Ledger.compileScript [|| validateGuess ||]))

gameDataScript :: String -> DataScript
gameDataScript =
    DataScript . Ledger.lifted . HashedString . plcSHA2_256 . C.pack

gameRedeemerScript :: String -> RedeemerScript
gameRedeemerScript =
    RedeemerScript . Ledger.lifted . ClearString . C.pack

gameAddress :: Address
gameAddress = Ledger.scriptAddress gameValidator

lock :: (WalletAPI m, WalletDiagnostics m) => String -> Value -> m ()
lock word vl = do
    let ds = gameDataScript word
    payToScript_ defaultSlotRange gameAddress vl ds

guess :: (WalletAPI m, WalletDiagnostics m) => String -> m ()
guess word = do
    let redeemer = gameRedeemerScript word
    collectFromScript defaultSlotRange gameValidator redeemer

-- | Tell the wallet to start watching the address of the game script
startGame :: WalletAPI m => m ()
startGame = startWatching gameAddress
