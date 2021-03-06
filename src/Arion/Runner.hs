module Arion.Runner(
    run
) where

import System.FSNotify (watchTree, withManager, WatchManager, Event)
import Data.Text (pack)
import Filesystem.Path.CurrentOS (fromText)
import System.Process (callCommand)
import Control.Monad (mapM_)
import System.FilePath.Find (find, always, extension, (==?), (||?))
import Control.Concurrent (threadDelay)
import Control.Monad (forever, void)
import Control.Exception (try, SomeException)
import Control.Concurrent (forkIO)
import System.Directory (canonicalizePath)
import Control.Applicative ((<$>))
import Control.Monad ((=<<))

import Arion.Types
import Arion.EventProcessor
import Arion.Utilities
import Arion.Help

run :: [String] -> IO ()
run args
    | "--help" `elem` args = putStrLn usage
    | length args >= 3 = let (path:sourceFolder:testFolder:_) = args
                         in withManager (startWatching path sourceFolder testFolder)
    | otherwise = putStrLn "Try arion --help for more information"

startWatching :: String -> String -> String -> WatchManager -> IO ()
startWatching path sourceFolder testFolder manager = do
                                         sourceFilePathAndContent <- mapM filePathAndContent =<< findHaskellFiles sourceFolder
                                         testFilePathAndContent <- mapM filePathAndContent =<< findHaskellFiles testFolder
                                         let sourceFiles = map (uncurry toSourceFile) sourceFilePathAndContent
                                         let testFiles = map (uncurry toTestFile) testFilePathAndContent
                                         let sourceToTestFileMap = associate sourceFiles testFiles
                                         _ <- watchTree manager (fromText $ pack path) (const True) (eventHandler sourceToTestFileMap sourceFolder testFolder)
                                         forever $ threadDelay maxBound

filePathAndContent :: String -> IO (FilePath, FileContent)
filePathAndContent relativePath = do
                          canonicalizedPath <- canonicalizePath relativePath
                          content <- readFile canonicalizedPath
                          return (canonicalizedPath, content)

findHaskellFiles :: String -> IO [String]
findHaskellFiles = find always (extension ==? ".hs" ||? extension ==? ".lhs")

eventHandler :: SourceTestMap -> String -> String -> Event -> IO ()
eventHandler sourceToTestFileMap sourceFolder testFolder event = let commands = processEvent sourceToTestFileMap sourceFolder testFolder event
                                                                 in mapM_ executeCommand commands

executeCommand :: Command -> IO ()
executeCommand command = let process = (try . callCommand) (show command) :: IO (Either SomeException ())
                         in void $ forkIO $ process >> return ()
