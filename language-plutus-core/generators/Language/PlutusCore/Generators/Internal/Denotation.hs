-- | This module defines tools for associating PLC terms with their corresponding
-- Haskell values.

{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE GADTs                     #-}

module Language.PlutusCore.Generators.Internal.Denotation
    ( Denotation(..)
    , DenotationContextMember(..)
    , DenotationContext(..)
    , denoteVariable
    , denoteTypedBuiltinName
    , insertVariable
    , insertTypedBuiltinName
    , typedBuiltinNames
    ) where

import           Language.PlutusCore.Constant
import           Language.PlutusCore.Name
import           Language.PlutusCore.Type

import           Language.PlutusCore.Generators.Internal.Dependent

import qualified Data.ByteString.Lazy                              as BSL
import qualified Data.ByteString.Lazy.Hash                         as Hash
import           Data.Dependent.Map                                (DMap)
import qualified Data.Dependent.Map                                as DMap
import           Data.Functor.Compose
import           Data.Proxy

-- | Haskell denotation of a PLC object. An object can be a 'BuiltinName' or a variable for example.
data Denotation object r = forall a. Denotation
    { _denotationObject :: object                         -- ^ A PLC object.
    , _denotationToTerm :: object -> Term TyName Name ()  -- ^ How to embed the object into a term.
    , _denotationItself :: a                              -- ^ The denotation of the object.
                                                          -- E.g. the denotation of 'AddInteger' is '(+)'.
    , _denotationScheme :: TypeScheme a r                 -- ^ The 'TypeScheme' of the object.
                                                          -- See 'intIntInt' for example.
    }

-- | A member of a 'DenotationContext'.
-- @object@ is existentially quantified, so the only thing that can be done with it,
-- is turning it into a 'Term' using '_denotationToTerm'.
data DenotationContextMember r =
    forall object. DenotationContextMember (Denotation object r)

-- | A context of 'DenotationContextMember's.
-- Each row is a mapping from a type to a list of things that can return that type.
-- For example it can contain a mapping from @integer@ to
--   1. a bound variable of type @integer@
--   2. a bound variable of functional type with the result being @integer@
--   3. the 'AddInteger' 'BuiltinName' or any other 'BuiltinName' which returns an @integer@.
newtype DenotationContext = DenotationContext
    { unDenotationContext :: DMap AsKnownType (Compose [] DenotationContextMember)
    }

-- Here the only search that we need to perform is the search for things that return an appropriate
-- @r@, be them variables or functions. Better if we also take types of arguments into account,
-- but it is not required as we can always generate an argument out of thin air in a rank-0 setting
-- (without @Void@).

-- | The resulting type of a 'TypeScheme'.
typeSchemeResult :: TypeScheme a r -> AsKnownType r
typeSchemeResult (TypeSchemeResult _)       = AsKnownType
typeSchemeResult (TypeSchemeArrow _ schB)   = typeSchemeResult schB
typeSchemeResult (TypeSchemeAllType _ schK) = typeSchemeResult $ schK Proxy

-- | Get the 'Denotation' of a variable.
denoteVariable :: KnownType r => Name () -> r -> Denotation (Name ()) r
denoteVariable name meta = Denotation name (Var ()) meta (TypeSchemeResult Proxy)

-- | Get the 'Denotation' of a 'TypedBuiltinName'.
denoteTypedBuiltinName :: TypedBuiltinName a r -> a -> Denotation BuiltinName r
denoteTypedBuiltinName (TypedBuiltinName name scheme) meta =
    Denotation name (Builtin () . BuiltinName ()) meta scheme

-- | Insert the 'Denotation' of an object into a 'DenotationContext'.
insertDenotation :: KnownType r => Denotation object r -> DenotationContext -> DenotationContext
insertDenotation denotation (DenotationContext vs) = DenotationContext $
    DMap.insertWith'
        (\(Compose xs) (Compose ys) -> Compose $ xs ++ ys)
        AsKnownType
        (Compose [DenotationContextMember denotation])
        vs

-- | Insert a variable into a 'DenotationContext'.
insertVariable :: KnownType a => Name () -> a -> DenotationContext -> DenotationContext
insertVariable name = insertDenotation . denoteVariable name

-- | Insert a 'TypedBuiltinName' into a 'DenotationContext'.
insertTypedBuiltinName :: TypedBuiltinName a r -> a -> DenotationContext -> DenotationContext
insertTypedBuiltinName tbn@(TypedBuiltinName _ scheme) meta =
    case typeSchemeResult scheme of
        AsKnownType -> insertDenotation (denoteTypedBuiltinName tbn meta)

-- Builtins that may fail are commented out, because we cannot handle them right now.
-- Look for "UNDEFINED BEHAVIOR" in "Language.PlutusCore.Generators.Internal.Dependent".
-- | A 'DenotationContext' that consists of 'TypedBuiltinName's.
typedBuiltinNames :: DenotationContext
typedBuiltinNames
    = insertTypedBuiltinName typedAddInteger           (+)
    . insertTypedBuiltinName typedSubtractInteger      (-)
    . insertTypedBuiltinName typedMultiplyInteger      (*)
--     . insertTypedBuiltinName typedDivideInteger        (nonZeroArg div)
--     . insertTypedBuiltinName typedRemainderInteger     (nonZeroArg rem)
--     . insertTypedBuiltinName typedQuotientInteger      (nonZeroArg quot)
--     . insertTypedBuiltinName typedModInteger           (nonZeroArg mod)
    . insertTypedBuiltinName typedLessThanInteger      (<)
    . insertTypedBuiltinName typedLessThanEqInteger    (<=)
    . insertTypedBuiltinName typedGreaterThanInteger   (>)
    . insertTypedBuiltinName typedGreaterThanEqInteger (>=)
    . insertTypedBuiltinName typedEqInteger            (==)
    . insertTypedBuiltinName typedConcatenate          (<>)
    . insertTypedBuiltinName typedTakeByteString       (BSL.take . fromIntegral)
    . insertTypedBuiltinName typedDropByteString       (BSL.drop . fromIntegral)
    . insertTypedBuiltinName typedSHA2                 Hash.sha2
    . insertTypedBuiltinName typedSHA3                 Hash.sha3
--     . insertTypedBuiltinName typedVerifySignature      verifySignature
    . insertTypedBuiltinName typedEqByteString         (==)
    $ DenotationContext mempty
