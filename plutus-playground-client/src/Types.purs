module Types where

import Prelude

import Ace.Halogen.Component (AceMessage, AceQuery)
import Auth (AuthStatus)
import Control.Comonad (class Comonad, extract)
import Control.Extend (class Extend, extend)
import Cursor (Cursor)
import Data.Array (mapWithIndex)
import Data.Array as Array
import Data.Either.Nested (Either2)
import Data.Functor.Coproduct.Nested (Coproduct2)
import Data.Generic.Rep (class Generic)
import Data.Lens (Lens, Lens', Prism', _2, over, prism', to, traversed, view)
import Data.Lens.Iso.Newtype (_Newtype)
import Data.Lens.Record (prop)
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype, unwrap)
import Data.NonEmpty ((:|))
import Data.RawJson (JsonEither, JsonTuple(..), RawJson(..))
import Data.String.Extra (toHex) as String
import Data.Symbol (SProxy(..))
import Data.Traversable (sequence, traverse)
import Data.Tuple (Tuple(..))
import Data.Tuple.Nested ((/\))
import Foreign (Foreign)
import Foreign.Class (class Decode, class Encode, encode)
import Foreign.Generic (aesonSumEncoding, defaultOptions, encodeJSON, genericDecode, genericEncode)
import Foreign.Object as FO
import Gist (Gist)
import Halogen.Chartist (ChartistMessage, ChartistQuery)
import Halogen.Component.ChildPath (ChildPath, cp1, cp2)
import Language.Haskell.Interpreter (SourceCode, InterpreterError, InterpreterResult)
import Ledger.Crypto (PubKey, _PubKey)
import Ledger.Extra (LedgerMap)
import Ledger.Tx (Tx)
import Ledger.TxId (TxIdOf)
import Ledger.Value (CurrencySymbol, TokenName, Value, _CurrencySymbol, _TokenName, _Value)
import Matryoshka (class Corecursive, class Recursive, Algebra, cata)
import Network.RemoteData (RemoteData)
import Playground.API (CompilationResult, Evaluation(..), EvaluationResult, FunctionSchema, KnownCurrency, SimpleArgumentSchema(..), SimulatorWallet, _FunctionSchema, _SimulatorWallet)
import Playground.API as API
import Servant.PureScript.Ajax (AjaxError)
import Test.QuickCheck.Arbitrary (class Arbitrary)
import Test.QuickCheck.Gen as Gen
import Validation (class Validation, ValidationError(..), WithPath, addPath, noPath, validate)
import Wallet.Emulator.Types (Wallet, _Wallet)
import Web.HTML.Event.DragEvent (DragEvent)

_simulatorWallet :: forall r a. Lens' { simulatorWallet :: a | r } a
_simulatorWallet = prop (SProxy :: SProxy "simulatorWallet")

_simulatorWalletWallet :: Lens' SimulatorWallet Wallet
_simulatorWalletWallet = _SimulatorWallet <<< prop (SProxy :: SProxy "simulatorWalletWallet")

_simulatorWalletBalance :: Lens' SimulatorWallet Value
_simulatorWalletBalance = _SimulatorWallet <<< prop (SProxy :: SProxy "simulatorWalletBalance")

_walletId :: Lens' Wallet Int
_walletId = _Wallet <<< prop (SProxy :: SProxy "getWallet")

_pubKey :: Lens' PubKey String
_pubKey = _PubKey <<< prop (SProxy :: SProxy "getPubKey")

_value :: Lens' Value (LedgerMap CurrencySymbol (LedgerMap TokenName Int))
_value = _Value <<< prop (SProxy :: SProxy "getValue")

_currencySymbol :: Lens' CurrencySymbol String
_currencySymbol = _CurrencySymbol <<< prop (SProxy :: SProxy "unCurrencySymbol")

_tokenName :: Lens' TokenName String
_tokenName = _TokenName <<< prop (SProxy :: SProxy "unTokenName")


data Action
  = Action
      { simulatorWallet :: SimulatorWallet
      , functionSchema :: FunctionSchema SimpleArgument
      }
  | Wait { blocks :: Int }

derive instance genericAction :: Generic Action _
derive instance eqAction :: Eq Action

instance encodeAction :: Encode Action where
  encode value = genericEncode (defaultOptions { unwrapSingleConstructors = true
                                               , sumEncoding = aesonSumEncoding
                                               }) value

instance decodeAction :: Decode Action where
  decode value = genericDecode (defaultOptions { unwrapSingleConstructors = true
                                               , sumEncoding = aesonSumEncoding
                                               }) value

_Action ::
  Prism'
    Action
    { simulatorWallet :: SimulatorWallet
    , functionSchema :: FunctionSchema SimpleArgument
    }
_Action = prism' Action f
  where
    f (Action r) = Just r
    f _ = Nothing

_Wait ::
  Prism'
    Action
    { blocks :: Int
    }
_Wait = prism' Wait f
  where
    f (Wait r) = Just r
    f _ = Nothing

_functionSchema :: forall a b r. Lens { functionSchema :: a | r} { functionSchema :: b | r} a b
_functionSchema = prop (SProxy :: SProxy "functionSchema")

_argumentSchema :: forall a b r. Lens {argumentSchema :: a | r} {argumentSchema :: b | r} a b
_argumentSchema = prop (SProxy :: SProxy "argumentSchema")

_functionName :: forall a b r. Lens {functionName :: a | r} {functionName :: b | r} a b
_functionName = prop (SProxy :: SProxy "functionName")

_blocks :: forall a b r. Lens { blocks :: a | r} { blocks :: b | r} a b
_blocks = prop (SProxy :: SProxy "blocks")

instance actionValidation :: Validation Action where
  validate (Wait _) = []
  validate (Action action) =
    Array.concat $ Array.mapWithIndex (\i v -> addPath (show i) <$> validate v) args
    where
      args :: Array SimpleArgument
      args = view (_functionSchema <<< _FunctionSchema <<< _argumentSchema) action

------------------------------------------------------------

-- | TODO: It should always be true that either toExpression returns a
-- `Just value` OR validate returns a non-empty array.
-- This suggests they should be the same function, returning either a group of error messages, or a valid expression.
toExpression :: Action -> Maybe API.Expression
toExpression (Wait wait) = Just $ API.Wait wait
toExpression (Action action) = do
  let wallet = view _simulatorWalletWallet action.simulatorWallet
  arguments <- jsonArguments
  pure $ API.Action { wallet, function, arguments }
  where
    function = view (_functionSchema <<< to unwrap <<< _functionName) action
    argumentSchema = view (_functionSchema <<< to unwrap <<< _argumentSchema) action

    jsonArguments =
      traverse (map (RawJson <<< encodeJSON) <<< simpleArgumentToJson) argumentSchema

toEvaluation :: SourceCode -> Simulation -> Maybe Evaluation
toEvaluation sourceCode (Simulation {actions, wallets}) = do
    program <- traverse toExpression actions
    pure $ Evaluation { wallets
                      , program
                      , sourceCode
                      , blockchain: []
                      }

------------------------------------------------------------

data Query a
  -- SubEvents.
  = HandleEditorMessage AceMessage a
  | HandleDragEvent DragEvent a
  | ActionDragAndDrop Int DragAndDropEventType DragEvent a
  | HandleDropEvent DragEvent a
  | HandleBalancesChartMessage ChartistMessage a
  -- Gist support.
  | CheckAuthStatus a
  | PublishGist a
  | SetGistUrl String a
  | LoadGist a
  -- Tabs.
  | ChangeView View a
  -- Editor.
  | LoadScript String a
  | CompileProgram a
  | ScrollTo { row :: Int, column :: Int } a
  -- Simulations
  | AddSimulationSlot a
  | SetSimulationSlot Int a
  | RemoveSimulationSlot Int a
  -- Wallets.
  | ModifyWallets WalletEvent a
  -- Actions.
  | ModifyActions ActionEvent a
  | EvaluateActions a
  | PopulateAction Int Int (FormEvent a)

data WalletEvent
  = AddWallet
  | RemoveWallet Int
  | ModifyBalance Int ValueEvent

data ValueEvent
  = SetBalance CurrencySymbol TokenName Int

data ActionEvent
  = AddAction Action
  | AddWaitAction Int
  | RemoveAction Int
  | SetWaitTime Int Int

data DragAndDropEventType
  = DragStart
  | DragEnd
  | DragEnter
  | DragOver
  | DragLeave
  | Drop

instance showDragAndDropEventType :: Show DragAndDropEventType where
  show DragStart = "DragStart"
  show DragEnd = "DragEnd"
  show DragEnter = "DragEnter"
  show DragOver = "DragOver"
  show DragLeave = "DragLeave"
  show Drop = "Drop"

data FormEvent a
  = SetIntField (Maybe Int) a
  | SetStringField String a
  | SetHexField String a
  | SetValueField ValueEvent a
  | AddSubField a
  | SetSubField Int (FormEvent a)
  | RemoveSubField Int a

derive instance functorFormEvent :: Functor FormEvent

instance extendFormEvent :: Extend FormEvent where
  extend f event@(SetIntField n _) = SetIntField n $ f event
  extend f event@(SetStringField s _) = SetStringField s $ f event
  extend f event@(SetHexField s _) = SetHexField s $ f event
  extend f event@(SetValueField e _) = SetValueField e $ f event
  extend f event@(AddSubField _) = AddSubField $ f event
  extend f event@(SetSubField n _) = SetSubField n $ extend f event
  extend f event@(RemoveSubField n _) = RemoveSubField n $ f event

instance comonadFormEvent :: Comonad FormEvent where
  extract (SetIntField _ a) = a
  extract (SetStringField _ a) = a
  extract (SetHexField _ a) = a
  extract (SetValueField _ a) = a
  extract (AddSubField a) = a
  extract (SetSubField _ e) = extract e
  extract (RemoveSubField _ e) = e

------------------------------------------------------------

type ChildQuery = Coproduct2 AceQuery ChartistQuery
type ChildSlot = Either2 EditorSlot BalancesChartSlot

data EditorSlot = EditorSlot
derive instance eqComponentEditorSlot :: Eq EditorSlot
derive instance ordComponentEditorSlot :: Ord EditorSlot

data BalancesChartSlot = BalancesChartSlot
derive instance eqComponentBalancesChartSlot :: Eq BalancesChartSlot
derive instance ordComponentBalancesChartSlot :: Ord BalancesChartSlot

cpEditor :: ChildPath AceQuery ChildQuery EditorSlot ChildSlot
cpEditor = cp1

cpBalancesChart :: ChildPath ChartistQuery ChildQuery BalancesChartSlot ChildSlot
cpBalancesChart = cp2

-----------------------------------------------------------

type Blockchain = Array (Array (JsonTuple (TxIdOf String) Tx))
type Signatures = Array (FunctionSchema SimpleArgumentSchema)
newtype Simulation = Simulation
  { signatures :: Signatures
  , actions :: Array Action
  , wallets :: Array SimulatorWallet
  , currencies :: Array KnownCurrency
  }

derive instance newtypeSimulation :: Newtype Simulation _
derive instance genericSimulation :: Generic Simulation _

instance encodeSimulation :: Encode Simulation where
  encode value = genericEncode (defaultOptions { unwrapSingleConstructors = true
                                               , sumEncoding = aesonSumEncoding
                                               }) value

instance decodeSimulation :: Decode Simulation where
  decode value = genericDecode (defaultOptions { unwrapSingleConstructors = true
                                               , sumEncoding = aesonSumEncoding
                                               }) value

type WebData = RemoteData AjaxError

newtype State = State
  { currentView :: View
  , compilationResult :: WebData (JsonEither InterpreterError (InterpreterResult CompilationResult))
  , simulations :: Cursor Simulation
  , actionDrag :: Maybe Int
  , evaluationResult :: WebData EvaluationResult
  , authStatus :: WebData AuthStatus
  , createGistResult :: WebData Gist
  , gistUrl :: Maybe String
  }

derive instance newtypeState :: Newtype State _

_currentView :: Lens' State View
_currentView = _Newtype <<< prop (SProxy :: SProxy "currentView")

_simulations :: Lens' State (Cursor Simulation)
_simulations = _Newtype <<< prop (SProxy :: SProxy "simulations")

_actionDrag :: Lens' State (Maybe Int)
_actionDrag = _Newtype <<< prop (SProxy :: SProxy "actionDrag")

_signatures :: Lens' Simulation Signatures
_signatures = _Newtype <<< prop (SProxy :: SProxy "signatures")

_actions :: Lens' Simulation (Array Action)
_actions = _Newtype <<< prop (SProxy :: SProxy "actions")

_wallets :: Lens' Simulation (Array SimulatorWallet)
_wallets = _Newtype <<< prop (SProxy :: SProxy "wallets")

_evaluationResult :: Lens' State (WebData EvaluationResult)
_evaluationResult = _Newtype <<< prop (SProxy :: SProxy "evaluationResult")

_compilationResult :: Lens' State (WebData (JsonEither InterpreterError (InterpreterResult CompilationResult)))
_compilationResult = _Newtype <<< prop (SProxy :: SProxy "compilationResult")

_authStatus :: Lens' State (WebData AuthStatus)
_authStatus = _Newtype <<< prop (SProxy :: SProxy "authStatus")

_createGistResult :: Lens' State (WebData Gist)
_createGistResult = _Newtype <<< prop (SProxy :: SProxy "createGistResult")

_gistUrl :: Lens' State (Maybe String)
_gistUrl = _Newtype <<< prop (SProxy :: SProxy "gistUrl")

_resultBlockchain :: Lens' EvaluationResult Blockchain
_resultBlockchain = _Newtype <<< prop (SProxy :: SProxy "resultBlockchain")

_knownCurrencies :: Lens' CompilationResult (Array KnownCurrency)
_knownCurrencies = _Newtype <<< prop (SProxy :: SProxy "knownCurrencies")

data View
  = Editor
  | Simulations
  | Transactions

derive instance eqView :: Eq View
derive instance genericView :: Generic View _

instance arbitraryView :: Arbitrary View where
  arbitrary = Gen.elements (Editor :| [ Simulations, Transactions ])

instance showView :: Show View where
  show Editor = "Editor"
  show Simulations = "Simulation"
  show Transactions = "Transactions"

------------------------------------------------------------

data SimpleArgument
  = SimpleInt (Maybe Int)
  | SimpleString (Maybe String)
  | SimpleHex (Maybe String)
  | SimpleArray SimpleArgumentSchema (Array SimpleArgument)
  | SimpleTuple (JsonTuple SimpleArgument SimpleArgument)
  | SimpleObject SimpleArgumentSchema (Array (JsonTuple String SimpleArgument))
  | ValueArgument SimpleArgumentSchema Value
  | Unknowable { context :: String, description :: String }

derive instance genericSimpleArgument :: Generic SimpleArgument _
derive instance eqSimpleArgument :: Eq SimpleArgument

instance encodeSimpleArgument :: Encode SimpleArgument where
  encode value = genericEncode (defaultOptions { unwrapSingleConstructors = true
                                               , sumEncoding = aesonSumEncoding
                                               }) value

instance decodeSimpleArgument :: Decode SimpleArgument where
  decode value = genericDecode (defaultOptions { unwrapSingleConstructors = true
                                               , sumEncoding = aesonSumEncoding
                                               }) value


toArgument :: Value -> SimpleArgumentSchema -> SimpleArgument
toArgument initialValue = rec
  where
    rec :: SimpleArgumentSchema -> SimpleArgument
    rec SimpleIntSchema = SimpleInt Nothing
    rec SimpleStringSchema = SimpleString Nothing
    rec SimpleHexSchema = SimpleHex Nothing
    rec (SimpleArraySchema field) = SimpleArray field []
    rec (SimpleTupleSchema (JsonTuple (fieldA /\ fieldB))) = SimpleTuple (JsonTuple (rec fieldA /\ rec fieldB))
    rec schema@(SimpleObjectSchema fields) =
        SimpleObject schema $ map JsonTuple $ over (traversed <<< _2) rec (map unwrap fields)
    rec schema@(ValueSchema fields) = ValueArgument schema initialValue
    rec (UnknownSchema context description) = Unknowable { context, description }

-- | This should just be `map` but we can't put an orphan instance on FunctionSchema. :-(
toArgumentLevel :: Value -> FunctionSchema SimpleArgumentSchema -> FunctionSchema SimpleArgument
toArgumentLevel initialValue = over (_Newtype <<< _argumentSchema <<< traversed) (toArgument initialValue)

------------------------------------------------------------

-- | This type serves as a functorised version of `SimpleArgument` so
-- we can do some recursive processing of the data without cluttering
-- the transformation with the iteration.
data SimpleArgumentF a
  = SimpleIntF (Maybe Int)
  | SimpleStringF (Maybe String)
  | SimpleHexF (Maybe String)
  | SimpleTupleF (JsonTuple a a)
  | SimpleArrayF SimpleArgumentSchema (Array a)
  | SimpleObjectF SimpleArgumentSchema (Array (JsonTuple String a))
  | ValueArgumentF SimpleArgumentSchema Value
  | UnknowableF { context :: String, description :: String }

instance functorSimpleArgumentF :: Functor SimpleArgumentF where
  map f (SimpleIntF x) = SimpleIntF x
  map f (SimpleStringF x) = SimpleStringF x
  map f (SimpleHexF x) = SimpleHexF x
  map f (SimpleTupleF (JsonTuple (Tuple x y))) = SimpleTupleF (JsonTuple (Tuple (f x) (f y)))
  map f (SimpleArrayF schema xs) = SimpleArrayF schema (map f xs)
  map f (SimpleObjectF schema xs) = SimpleObjectF schema (map (map f) xs)
  map f (ValueArgumentF schema x) = ValueArgumentF schema x
  map f (UnknowableF x) = UnknowableF x

derive instance eqSimpleArgumentF :: Eq a => Eq (SimpleArgumentF a)

instance recursiveSimpleArgument :: Recursive SimpleArgument SimpleArgumentF where
  project (SimpleInt x) = SimpleIntF x
  project (SimpleString x) = SimpleStringF x
  project (SimpleHex x) = SimpleHexF x
  project (SimpleTuple x) = SimpleTupleF x
  project (SimpleArray schema xs) = SimpleArrayF schema xs
  project (SimpleObject schema xs) = SimpleObjectF schema xs
  project (ValueArgument schema x) = ValueArgumentF schema x
  project (Unknowable x) = UnknowableF x

instance corecursiveSimpleArgument :: Corecursive SimpleArgument SimpleArgumentF where
  embed (SimpleIntF x) = SimpleInt x
  embed (SimpleStringF x) = SimpleString x
  embed (SimpleHexF x) = SimpleHex x
  embed (SimpleTupleF xs) = SimpleTuple xs
  embed (SimpleArrayF schema xs) = SimpleArray schema xs
  embed (SimpleObjectF schema xs) = SimpleObject schema xs
  embed (ValueArgumentF schema x) = ValueArgument schema x
  embed (UnknowableF x) = Unknowable x

------------------------------------------------------------

instance validationSimpleArgument :: Validation SimpleArgument where
  validate = cata algebra
    where
      algebra :: Algebra SimpleArgumentF (Array (WithPath ValidationError))
      algebra (SimpleIntF (Just _)) = []
      algebra (SimpleIntF Nothing) = [ noPath Required ]

      algebra (SimpleStringF (Just _)) = []
      algebra (SimpleStringF Nothing) = [ noPath Required ]

      algebra (SimpleHexF (Just _)) = []
      algebra (SimpleHexF Nothing) = [ noPath Required ]

      algebra (SimpleTupleF (JsonTuple (Tuple xs ys))) =
        Array.concat [ addPath "_1" <$> xs
                     , addPath "_2" <$> ys
                     ]

      algebra (SimpleArrayF schema xs) =
        Array.concat $ mapWithIndex (\i values-> addPath (show i) <$> values) xs

      algebra (SimpleObjectF schema xs) =
        Array.concat $ map (\(JsonTuple (Tuple name values)) -> addPath name <$> values) xs

      algebra (ValueArgumentF schema x) = []

      algebra (UnknowableF _) = [ noPath Unsupported ]

simpleArgumentToJson :: SimpleArgument -> Maybe Foreign
simpleArgumentToJson arg = cata algebra arg
  where
    algebra :: Algebra SimpleArgumentF (Maybe Foreign)
    algebra (SimpleIntF (Just n)) = Just $ encode n
    algebra (SimpleIntF Nothing) = Nothing
    algebra (SimpleStringF (Just str)) = Just $ encode str
    algebra (SimpleStringF Nothing) = Nothing
    algebra (SimpleHexF (Just str)) = Just $ encode $ String.toHex str
    algebra (SimpleHexF Nothing) = Nothing
    algebra (SimpleTupleF (JsonTuple (Just fieldA /\ Just fieldB))) = Just $ encode [ fieldA, fieldB ]
    algebra (SimpleTupleF _) = Nothing
    algebra (SimpleArrayF _ fields) = Just $ encode fields
    algebra (SimpleObjectF _ fields) = encodeFields fields
      where
        encodeFields :: Array (JsonTuple String (Maybe Foreign)) -> Maybe Foreign
        encodeFields xs = map (encode <<< FO.fromFoldable) $ prepareObject xs
        prepareObject :: Array (JsonTuple String (Maybe Foreign)) -> Maybe (Array (Tuple String Foreign))
        prepareObject = traverse processTuples
        processTuples :: JsonTuple String (Maybe Foreign) -> Maybe (Tuple String Foreign)
        processTuples = unwrap >>> sequence
    algebra (ValueArgumentF _ x) = Just $ encode x
    algebra (UnknowableF _) = Nothing

--- Language.Haskell.Interpreter ---

_result :: forall s a. Lens' {result :: a | s} a
_result = prop (SProxy :: SProxy "result")

_warnings :: forall s a. Lens' {warnings :: a | s} a
_warnings = prop (SProxy :: SProxy "warnings")
