module Reach.CompilerTool (CompilerToolOpts (..), makeCompilerOpts, compilerToolMain) where

import Control.Monad
import qualified Filesystem.Path.CurrentOS as FP
import Reach.Compiler
import System.Directory
import Reach.Util (Top(..))

data CompilerToolOpts = CompilerToolOpts
  { cto_outputDir :: FilePath
  , cto_dirDotReach :: FilePath
  , cto_canGit :: Bool
  , cto_source :: FilePath
  , cto_tops :: [String]
  , cto_intermediateFiles :: Bool
  }

makeCompilerOpts :: CompilerToolOpts -> IO CompilerOpts
makeCompilerOpts CompilerToolOpts {..} = do
  let srcp = cto_source
  let outd = cto_outputDir
  let outdp = FP.decodeString outd
  let outn ext = FP.encodeString $ FP.append outdp $ (FP.filename $ FP.decodeString srcp) `FP.replaceExtension` ext
  createDirectoryIfMissing True outd
  return $
    CompilerOpts
      { output = outn
      , source = srcp
      , tops = if null cto_tops then CompileAll else CompileJust cto_tops
      , intermediateFiles = cto_intermediateFiles
      , dirDotReach = cto_dirDotReach
      , canGit = cto_canGit
      }

compilerToolMain :: CompilerToolOpts -> IO ()
compilerToolMain = makeCompilerOpts >=> compile
