{-# LANGUAGE OverloadedStrings #-}
module Kurokos.Asset.Internal.Types where

import qualified Data.ByteString      as BS
import qualified Data.Map             as M
import qualified Data.Text            as T
import           Data.Yaml            (FromJSON (..), (.:), (.:?))
import qualified Data.Yaml            as Y
import Data.Maybe (fromMaybe)

type Ident = T.Text

data AssetInfo = AssetInfo
  { aiIdent     :: Maybe Ident
  , aiDirectory :: Maybe FilePath
  , aiFileName  :: String
  } deriving Show

instance FromJSON AssetInfo where
  parseJSON (Y.Object v) = AssetInfo
    <$> v .:? "id"
    <*> v .:? "dir"
    <*> v .:  "file"
  parseJSON _ = fail "Expected Object for AssetInfo"

data PatternsInDir = PatternsInDir
  { pidIdPrefix  :: Maybe Ident
  , pidIdFname   :: Bool
  , pidDirectory :: FilePath
  , pidPattern   :: String
  , pidIgnores   :: [String]
  }

instance FromJSON PatternsInDir where
  parseJSON (Y.Object v) = PatternsInDir
    <$> v .:? "id"
    <*> (fromMaybe True <$> v .:? "id-fname")
    <*> v .: "dir"
    <*> v .: "pattern"
    <*> (fromMaybe [] <$> v .:? "ignores")
  parseJSON _            = fail "Expected Object for PatternsInDir"

data AssetFile = AssetFile [AssetInfo] [PatternsInDir]

instance FromJSON AssetFile where
  parseJSON (Y.Object v) = AssetFile
    <$> (fromMaybe [] <$> v .:? "files")
    <*> (fromMaybe [] <$> v .:? "patterns")
  parseJSON _            = fail "Expected Object for AssetFile"

newtype AssetList =
  AssetList { unAssetList :: [AssetInfo] }
  deriving Show

instance Monoid AssetList where
  mempty = AssetList []
  mappend (AssetList xs) (AssetList ys) = AssetList $ xs ++ ys

newtype RawAssetManager = RawAssetManager
  { unAssetManager :: M.Map Ident (FilePath, BS.ByteString)
  }
