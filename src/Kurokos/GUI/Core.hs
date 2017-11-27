{-# LANGUAGE ExistentialQuantification  #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE Strict                     #-}
{-# LANGUAGE StrictData                 #-}
{-# LANGUAGE TemplateHaskell            #-}
module Kurokos.GUI.Core where

import           Control.Exception.Safe (MonadMask)
import           Control.Lens
import           Control.Monad.Reader
import           Control.Monad.State
import           Data.Int               (Int64)
import           Data.Text              (Text)

import qualified SDL
import qualified SDL.Font               as Font

import           Kurokos.GUI.Def        (RenderEnv)

-- data Direction
--   = DirH -- Horizontal
--   | DirV -- Vertical
--   deriving Show

class Widget a where
  showW :: a -> String
  render :: (MonadIO m, MonadMask m) => RenderEnv m => a -> m ()

type Key = Int64
newtype SingleKey = SingleKey Key deriving Show
newtype ContainerKey = ContainerKey Key deriving Show

data WidgetTree
  = forall a. (Widget a)
  => Single SingleKey a | Container ContainerKey [WidgetTree]

instance Show WidgetTree where
  show (Single (SingleKey key) a)        = show key ++ "<" ++ showW a ++ ">"
  show (Container (ContainerKey key) ws) = show key ++ "@" ++ show ws

newtype GuiEnv = GuiEnv
  { geFont :: Font.Font
  }

data GuiState = GuiState
  { _gsSCnt  :: Key
  , _gsCCnt  :: Key
  --
  , _gsWTree :: WidgetTree
  } deriving Show

makeLenses ''GuiState

getWidgetTree :: GuiState -> WidgetTree
getWidgetTree = _gsWTree

newtype GuiT m a = GuiT {
    runGT :: ReaderT GuiEnv (StateT GuiState m) a
  } deriving (Functor, Applicative, Monad, MonadIO, MonadReader GuiEnv, MonadState GuiState)

runGuiT :: Monad m => GuiEnv -> GuiState -> GuiT m a -> m GuiState
runGuiT env gst k = execStateT (runReaderT (runGT k) env) gst

newGui :: Monad m => GuiEnv -> GuiT m () -> m GuiState
newGui env = runGuiT env gs0
  where
    gs0 = GuiState 0 1 (Container (ContainerKey 0) [])

genSingle :: (Widget a, Monad m) => a -> GuiT m WidgetTree
genSingle a = do
  key <- SingleKey <$> use gsSCnt
  gsSCnt += 1
  return $ Single key a

genContainer :: Monad m => [WidgetTree] -> GuiT m WidgetTree
genContainer ws = do
  key <- ContainerKey <$> use gsCCnt
  gsCCnt += 1
  return $ Container key ws

putWT :: Monad m => WidgetTree -> GuiT m ()
putWT wt = gsWTree .= wt

renderGUI :: (RenderEnv m, MonadIO m, MonadMask m) => GuiState -> m ()
renderGUI gst = go $ gst^.gsWTree
  where
    go (Single _ a)     = render a
    go (Container _ ws) = mapM_ go ws
