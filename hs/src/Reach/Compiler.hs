module Reach.Compiler (CompilerOpts (..), compile, all_connectors) where

import qualified Data.HashMap.Strict as HM
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import qualified Data.Text.Lazy.IO as LTIO
import qualified Reach.Parser.Common as P
import Reach.AddCounts
import Reach.AST.DL
import Reach.Backend.JS
import Reach.Connector
import Reach.Connector.ALGO
import Reach.Connector.ETH_Solidity
import Reach.EPP
import Reach.EraseLogic
import Reach.Eval
import Reach.Linearize
import Reach.Optimize
import Reach.Parser (JSBundle(..), gatherDeps_top)
import Reach.Texty
import Reach.Util
import Reach.Verify
import Reach.Eval.Core (SLLibs, e_lifts, defaultApp, getLibExe)
import Reach.AST.Base (SLVar)
import Reach.AST.SL (SLPrimitive(SLPrim_App_Delay), SLVal (SLV_Prim), sss_val)
import Control.Monad (forM_)
import Reach.Eval.Module (evalLibs, findTops)
import Control.Monad.Reader (runReaderT)
import Data.IORef (readIORef, writeIORef)
import System.Directory

data CompilerOpts = CompilerOpts
  { output :: T.Text -> String
  , source :: FilePath
  , tops :: Top
  , intermediateFiles :: Bool
  , dirDotReach :: FilePath
  , canGit :: Bool
  }

all_connectors :: Connectors
all_connectors =
  M.fromList $
    map
      (\x -> (conName x, x))
      [ connect_eth
      , connect_algo
      ]

dropOtherTops :: SLVar -> SLLibs -> SLLibs
dropOtherTops which =
  M.map (M.filterWithKey (\ k v ->
      case sss_val v of
        SLV_Prim SLPrim_App_Delay {} -> k == which
        _ -> True ))

maybeDefaultApp :: JSBundle -> SLLibs -> [String] -> (SLLibs, [String])
maybeDefaultApp (JSBundle mods) libm = \case
  []   -> do
    let name = "default" -- `default` will never be accepted by the parser as an identifier
    let exe = getLibExe mods
    (M.insert exe (M.insert name defaultApp $ libm M.! exe) libm, [name])
  tops -> (libm, tops)

compile :: CompilerOpts -> IO ()
compile copts = do
  let outn = output copts
  let outnMay outn_ = case intermediateFiles copts of
        True -> Just outn_
        False -> Nothing
  let interOut outn_ = case outnMay outn_ of
        Just f -> LTIO.writeFile . f
        Nothing -> \_ _ -> return ()
  dirDotReach' <- makeAbsolute $ dirDotReach copts
  djp <- runReaderT (gatherDeps_top $ source copts) P.ParserOpts
    { P.dirDotReach = dirDotReach'
    , P.canGit = canGit copts
    }
  interOut outn "bundle.js" $ render $ pretty djp
  -- Either compile all the Reach.Apps or those specified by user
  evalEnv <- defaultEnv all_connectors
  let JSBundle mods = djp
  _libm <- flip runReaderT evalEnv $ evalLibs all_connectors mods
  lifts <- readIORef $ e_lifts evalEnv
  let (libm, whichs) = maybeDefaultApp djp _libm $ case tops copts of
        CompileAll -> findTops djp _libm
        CompileJust tops -> tops
  forM_ whichs $ \ which -> do
      let addWhich = ((T.pack which <> ".") <>)
      let woutn = outn . addWhich
      let woutnMay = outnMay woutn
      let winterOut = interOut woutn
      let showp :: (forall a. Pretty a => T.Text -> a -> IO ())
          showp l = winterOut l . render . pretty
      let showp' :: (forall a. Pretty a => String -> a -> IO ())
          showp' = showp . T.pack
      let libm' = dropOtherTops which libm
      -- Reutilize env from parsing module, but remove any lifts
      -- from processing previous top
      writeIORef (e_lifts evalEnv) lifts
      dl <- compileBundle evalEnv all_connectors djp libm' which
      let DLProg _ (DLOpts {..}) _ _ _ _ _ = dl
      let connectors = map (all_connectors M.!) dlo_connectors
      showp "dl" dl
      ll <- linearize showp' dl
      ol <- optimize ll
      showp "ol" ol
      let vconnectors =
            case dlo_verifyPerConnector of
            False -> Nothing
            True -> Just connectors
      verify woutnMay vconnectors ol >>= maybeDie
      el <- erase_logic ol
      showp "el" el
      pil <- epp el
      showp "pil" pil
      pl <- add_counts pil
      showp "pl" pl
      let runConnector c = (,) (conName c) <$> conGen c woutnMay pl
      crs <- HM.fromList <$> mapM runConnector connectors
      backend_js woutn crs pl
      return ()
