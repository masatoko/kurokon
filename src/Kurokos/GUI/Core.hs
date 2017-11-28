{-# LANGUAGE ExistentialQuantification  #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE Strict                     #-}
{-# LANGUAGE StrictData                 #-}
{-# LANGUAGE TemplateHaskell            #-}
module Kurokos.GUI.Core where

import           Control.Exception.Safe    (MonadMask)
import qualified Control.Exception.Safe    as E
import           Control.Lens
import           Control.Monad.Reader
import           Control.Monad.State
import           Data.Int                  (Int64)
import           Data.Text                 (Text)
import           Foreign.C.Types           (CInt)
import           Linear.V2

import           SDL                       (($=))
import qualified SDL
import qualified SDL.Font                  as Font

import           Kurokos.GUI.Def           (RenderEnv (..))
import           Kurokos.GUI.Import
import           Kurokos.GUI.Types
import           Kurokos.GUI.Widget
import           Kurokos.GUI.Widget.Render

-- class Widget a where
--   showW :: a -> String
--   render :: (MonadIO m, MonadMask m) => RenderEnv m => a -> m ()

type Key = Int64
newtype SingleKey = SingleKey Key deriving Show
newtype ContainerKey = ContainerKey Key deriving Show

data WidgetTree
  = Single
      { singleKey :: SingleKey
      , wtTexture :: SDL.Texture
      , wtPos     :: GuiPos
      , wtSize    :: GuiSize
      , wtWidget  :: Widget
      }
  | Container
      { containerKey :: ContainerKey
      , wtPos        :: GuiPos
      , wtSize       :: GuiSize
      , wtChildren   :: [WidgetTree]
      }

instance Show WidgetTree where
  show Single{..} = show key ++ show wtWidget
    where (SingleKey key) = singleKey
  show Container{..} = show key ++ show wtChildren
    where (ContainerKey key) = containerKey

newtype GuiEnv = GuiEnv
  { geFont :: Font.Font
  }

data GUI = GUI
  { _gSCnt  :: Key
  , _gCCnt  :: Key
  --
  , _gWTree :: WidgetTree
  } deriving Show

makeLenses ''GUI

getWidgetTree :: GUI -> WidgetTree
getWidgetTree = _gWTree

newtype GuiT m a = GuiT {
    runGT :: ReaderT GuiEnv (StateT GUI m) a
  } deriving (Functor, Applicative, Monad, MonadIO, MonadReader GuiEnv, MonadState GUI)

runGuiT :: Monad m => GuiEnv -> GUI -> GuiT m a -> m GUI
runGuiT env g k = execStateT (runReaderT (runGT k) env) g

instance MonadTrans GuiT where
  lift = GuiT . lift . lift

newGui :: (RenderEnv m, MonadIO m, E.MonadThrow m) => GuiEnv -> GuiT m () -> m GUI
newGui env initializer = do
  winSize <- SDL.get . SDL.windowSize =<< getWindow
  let gui = GUI 0 1 (Container (ContainerKey 0) (pure 0) winSize [])
  runGuiT env gui initializer

genSingle :: (RenderEnv m, MonadIO m, MonadMask m)
  => GuiPos -> GuiSize -> Widget -> GuiT m WidgetTree
genSingle pos size w = do
  key <- SingleKey <$> use gSCnt
  gSCnt += 1
  lift $ withRenderer $ \r -> do
    tex <- SDL.createTexture r SDL.RGBA8888 SDL.TextureAccessTarget size
    SDL.textureBlendMode tex $= SDL.BlendAlphaBlend
    E.bracket_ (SDL.rendererRenderTarget r $= Just tex)
               (SDL.rendererRenderTarget r $= Nothing)
               (renderWidget r size w)
    return $ Single key tex pos size w

genContainer :: Monad m
  => GuiPos -> GuiSize -> [WidgetTree] -> GuiT m WidgetTree
genContainer pos size ws = do
  key <- ContainerKey <$> use gCCnt
  gCCnt += 1
  return $ Container key pos size ws

putWT :: Monad m => WidgetTree -> GuiT m ()
putWT wt = gWTree .= wt

renderGUI :: (RenderEnv m, MonadIO m, MonadMask m) => GUI -> m ()
renderGUI g =
  go (pure 0) (g^.gWTree)
  where
    go pos0 Single{..} =
      renderTexture wtTexture $ SDL.Rectangle pos' wtSize
      where
        pos' = SDL.P $ pos0 + wtPos
    go pos0 Container{..} =
      mapM_ (go $ pos0 + wtPos) wtChildren
