module Kurokos.Asset.Internal.Archive.Importer
  ( importAssetManager
  ) where

import           Control.Monad                    (foldM)
import qualified Data.ByteString.Char8            as C8
import           Data.Int                         (Int64)
import           Data.List.Split                  (splitOn)
import qualified Data.Map                         as M
import qualified Data.Text                        as T
import           System.IO.MMap
-- import qualified Control.Exception                as E
-- import qualified Data.ByteString                  as BS
-- import           Data.List                        (nub)
-- import qualified Data.Text.IO                     as T
-- import           Data.Word                        (Word8)
-- import           System.FilePath.Posix

import           Kurokos.Asset.Internal.Archive.Encrypt (decode)
import           Kurokos.Asset.Internal.Archive.Util    (Password, unpackSize, (<+>))
import           Kurokos.Asset.Internal.Types

importAssetManager :: Password -> FilePath -> IO RawAssetManager
importAssetManager pass orgPath = do
  (headerSize, as) <- readHeaderInfo pass orgPath
  RawAssetManager . snd <$> foldM work (headerSize, M.empty) as
  where
    work (offset, amap) (size, ident, path) = do
      bytes <- decode (pass <+> offset) <$> mmapFileByteString orgPath range
      let amap' = M.insert ident (path, bytes) amap
      return (offset + fromIntegral size, amap')
      where
        range = Just (offset, size)

readHeaderInfo :: Password -> FilePath -> IO (Int64, [(Int, Ident, FilePath)])
readHeaderInfo pass orgPath = do
  headerSize <- unpackSize . decode (pass <+> 0) <$> read' 0 4
  headerPart <- decode (pass <+> 4) <$> read' 4 (fromIntegral headerSize - 4)
  info <- toFileInfo . C8.unpack $ headerPart
  return (headerSize, info)
  where
    read' from size = mmapFileByteString orgPath (Just (from, size))

    toFileInfo = mapM toInfo . init . splitOn "\n"
    toInfo part = do
      size' <- readIO size
      return (size', T.pack ident, path)
      where
        (size, _:rest) = break (== ';') part
        (ident, _:path) = break (== ';') rest
