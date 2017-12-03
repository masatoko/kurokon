{-# LANGUAGE OverloadedStrings #-}

module Main where

import qualified Data.ByteString.Char8 as B
import qualified Data.Map.Strict       as M
import qualified Data.Text             as T
import qualified Data.Text.IO          as T
import           System.FilePath.Posix

import qualified Kurokos.Archive       as ARC

arcPath :: FilePath
arcPath = "_archived/result.arc"

key :: B.ByteString
key = "secret"

main :: IO ()
main = do
  B.putStrLn . ARC.decode key . ARC.encode key $ "KONNICHIWA!" -- Test decode and encode
  archiveFiles
  extract
  readFromArc

-- Archive files
archiveFiles :: IO ()
archiveFiles =
  ARC.archiveF key arcPath "_target" isValidPath
  where
    isValidPath path =
      isHeadValid name && all isValidDir dirs
      where
        name = takeFileName path

        isHeadValid ('@':_) = False
        isHeadValid _       = True

        dirs = splitDirectories . dropFileName $ path
        isValidDir ('_':_) = False
        isValidDir _       = True

-- Extract archive
extract :: IO ()
extract = do
  ARC.extractFiles key arcPath "_extracted"
  putStrLn "\n=== showFiles ==="
  ARC.showFiles key arcPath >>= putStrLn
  putStrLn "\n=== text1.txt ==="
  ARC.readArchiveText key arcPath "text1.txt" >>= T.putStrLn
  putStrLn "\n=== child/text2.txt ==="
  ARC.readArchiveStr key arcPath "child/text2.txt" >>= putStrLn
  ARC.readArchiveStr key arcPath "child/child1/../text2.txt" >>= putStrLn
  putStrLn "\n=== directoryFiles ==="
  ARC.directoryFiles key arcPath "child" >>= print
  putStrLn "\n=== directoryDirs ==="
  ARC.directoryDirs key arcPath "child" >>= print
  ARC.directoryDirs key arcPath "" >>= print
  putStrLn "\n=== directoryFiles ==="
  ARC.directoryFiles key arcPath "child" >>= print
  ARC.directoryFiles key arcPath "" >>= print

-- Read an archive file as 'Archive' data
readFromArc :: IO ()
readFromArc = do
  putStrLn "\n=== Read archive ==="
  arc <- ARC.readArchive key arcPath -- read an archive file and make 'Archive' data
  bs <- ARC.getFileBS key "child/child1/txt_child1.txt" arc -- read data from the Archive data
  print bs