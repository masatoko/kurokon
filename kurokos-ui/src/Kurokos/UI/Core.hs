{-# LANGUAGE ExistentialQuantification  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE Strict                     #-}
{-# LANGUAGE StrictData                 #-}
{-# LANGUAGE TemplateHaskell            #-}
module Kurokos.UI.Core where

import           Control.Concurrent.MVar
import qualified Control.Exception        as E
import           Control.Lens
import           Control.Monad.Reader
import           Control.Monad.State
import           Data.ByteString          (ByteString)
import qualified Data.Map                 as M
import           Data.Maybe               (fromMaybe, isJust)
import           Data.Monoid              ((<>))
import           Data.Text                (Text)
import qualified Data.Text                as T
import           Linear.V2

import           SDL                      (($=))
import qualified SDL
import qualified SDL.Font                 as Font

import qualified Kurokos.Asset            as Asset
import qualified Kurokos.Asset.SDL        as Asset
import qualified Kurokos.RPN              as RPN

import           Kurokos.UI.Color
import           Kurokos.UI.Color.Scheme  (ColorScheme, lookupColorOfWidget)
import           Kurokos.UI.Event         (GuiEvent)
import           Kurokos.UI.Import
import           Kurokos.UI.Types
import           Kurokos.UI.Widget
import           Kurokos.UI.Widget.Names  (widgetNameOf)
import           Kurokos.UI.Widget.Render
import           Kurokos.UI.WidgetTree    (WidgetTree (..))
import qualified Kurokos.UI.WidgetTree    as WT

type CtxWidget = (WContext, Widget)
type GuiWidgetTree = WidgetTree CtxWidget

-- Update visibiilty in WidgetState
updateVisibility :: GuiWidgetTree -> GuiWidgetTree
updateVisibility = work True
  where
    work _    Null            = Null
    work vis0 (Fork u a mc o) =
      Fork (work vis0 u) a' (work vis' <$> mc) (work vis0 o)
      where
        atr = a^._1.ctxAttrib -- Original attribute
        vis' = vis0 && atr^.visible -- Current state
        a' = a & _1 . ctxWidgetState . wstVisible .~ vis'

-- Update global position in WidgetState
updateLayout :: GuiWidgetTree -> GuiWidgetTree
updateLayout wt0 = fst $ work wt0 Unordered False (P $ V2 0 0)
  where
    help f (a,p) = f p >> return a
    modsize Unordered       _ = return ()
    modsize VerticalStack   p = _y .= (p^._y)
    modsize HorizontalStack p = _x .= (p^._x)

    work Null            _   _            p0 = (Null, p0)
    work (Fork u a mc o) ct0 parentLayout p0 = runState go p0
      where
        wst = a^._1.ctxWidgetState
        shouldLayout = parentLayout || (a^._1.ctxNeedsLayout)
        ct' = fromMaybe Unordered $ a^._1.ctxContainerType
        go = do
          -- Under
          u' <- help (modsize ct0) . work u ct0 parentLayout =<< get
          -- CtxWidget
          pos <- get
          let pos' = case ct0 of
                      Unordered -> p0 + (wst^.wstPos)
                      _         -> pos
              a' = if shouldLayout
                      then a & _1 . ctxWidgetState . wstGlobalPos .~ pos'
                             & _1 . ctxNeedsLayout .~ False
                      else a
          modsize ct0 $ pos' + P (wst^.wstSize)
          -- Children
          mc' <- case mc of
            Nothing -> return Nothing
            Just c  -> fmap Just $ help (modsize ct0) $ work c ct' shouldLayout pos'
          -- Over
          o' <- help (modsize ct0) . work o ct0 parentLayout =<< get
          return $ Fork u' a' mc' o'

data GuiEnv = GuiEnv
  { geAssetManager :: Asset.SDLAssetManager
  , geColorScheme  :: ColorScheme
  }

data GuiState = GuiState
  { _gstKeyCnt :: Key
  -- ^ Counter for WidgetTree ID
  , _gstWTree  :: GuiWidgetTree
  }

makeLenses ''GuiState

newtype GUI = GUI { _unGui :: (GuiEnv, GuiState) }

makeLenses ''GUI

getWidgetTree :: GUI -> WidgetTree Widget
getWidgetTree = fmap snd . view gstWTree . snd . _unGui

newtype GuiT m a = GuiT {
    runGT :: ReaderT GuiEnv (StateT GuiState m) a
  } deriving (Functor, Applicative, Monad, MonadIO, MonadReader GuiEnv, MonadState GuiState)

runGuiT :: Monad m => GUI -> GuiT m a -> m GUI
runGuiT (GUI (env, gst)) k = do
  gst' <- execStateT (runReaderT (runGT k) env) gst
  return $ GUI (env, gst')

instance MonadTrans GuiT where
  lift = GuiT . lift . lift

newGui :: (RenderEnv m, MonadIO m)
  => GuiEnv -> GuiT m () -> m GUI
newGui env initializer = do
  g1 <- runGuiT g0 initializer
  readyRender $ g1 & unGui._2.gstWTree %~ WT.balance
  where
    g0 = GUI (env, gst0)
    gst0 = GuiState 0 Null

freeGui :: MonadIO m => GUI -> m ()
freeGui g =
  mapM_ (freeWidget . snd) $ g^.unGui._2.gstWTree

modifyGui :: (Monad m, Functor m) => (GUI -> GUI) -> GuiT m ()
modifyGui f = do
  GUI (_,stt) <- f . GUI <$> ((,) <$> ask <*> get)
  put stt

getContextColorOfWidget :: (MonadReader GuiEnv m, MonadIO m) => Widget -> m ContextColor
getContextColorOfWidget w = do
  schemeMap <- asks geColorScheme
  liftIO $ case lookupColorOfWidget w schemeMap of
    Left err -> E.throwIO $ userError err
    Right a  -> return a

genSingle :: (RenderEnv m, MonadIO m)
  => Maybe WidgetIdent -> Maybe ContextColor -> V2 UExp -> V2 UExp -> Widget -> GuiT m GuiWidgetTree
genSingle mIdent mColor pos size w = do
  key <- WTKey <$> use gstKeyCnt
  gstKeyCnt += 1
  pos' <- case fromUExpV2 pos of
            Left err -> E.throw $ userError err
            Right v  -> return v
  size' <- case fromUExpV2 size of
            Left err -> E.throw $ userError err
            Right v  -> return v
  tex <- lift $ withRenderer $ \r ->
    SDL.createTexture r SDL.RGBA8888 SDL.TextureAccessTarget (pure 1)
  ctxCol <- maybe (getContextColorOfWidget w) return mColor
  let ctx = WContext key mIdent Nothing (attribOf w) True True iniWidgetState ctxCol tex pos' size'
  return $ Fork Null (ctx, w) Nothing Null

genContainer :: (RenderEnv m, MonadIO m)
  => Maybe WidgetIdent -> ContainerType -> Maybe ContextColor -> V2 UExp -> V2 UExp -> GuiT m GuiWidgetTree
genContainer mIdent ct mColor pos size = do
  key <- WTKey <$> use gstKeyCnt
  gstKeyCnt += 1
  pos' <- case fromUExpV2 pos of
            Left err -> E.throw $ userError err
            Right v  -> return v
  size' <- case fromUExpV2 size of
            Left err -> E.throw $ userError err
            Right v  -> return v
  tex <- lift $ withRenderer $ \r ->
    SDL.createTexture r SDL.RGBA8888 SDL.TextureAccessTarget (pure 1)
  let w = Transparent
  ctxCol <- maybe (getContextColorOfWidget w) return mColor
  let ctx = WContext key mIdent (Just ct) (attribOf w) True True iniWidgetState ctxCol tex pos' size'
  return $ Fork Null (ctx,w) (Just Null) Null

appendRoot :: Monad m => GuiWidgetTree -> GuiT m ()
appendRoot wt = modify $ over gstWTree (wt <>)

prependRoot :: Monad m => GuiWidgetTree -> GuiT m ()
prependRoot wt = modify $ over gstWTree (<> wt)

-- Rendering GUI

setAllNeedsLayout :: GUI -> GUI
setAllNeedsLayout =
  over (unGui._2.gstWTree) (fmap work)
  where
    work = set (_1 . ctxNeedsLayout) True

setAllNeedsRender :: GUI -> GUI
setAllNeedsRender =
  over (unGui._2.gstWTree) (fmap work)
  where
    work = set (_1 . ctxNeedsRender) True

-- | Ready for rendering. Call this at the end of Update
readyRender :: (RenderEnv m, MonadIO m) => GUI -> m GUI
readyRender g = do
  V2 w h <- getWindowSize
  let vmap = M.fromList
        [ (keyWidth, w)
        , (keyHeight, h)
        , (keyWinWidth, w)
        , (keyWinHeight, h)]
  wt <- go vmap $ g^.unGui._2.gstWTree
  return $ g & unGui._2.gstWTree .~ (updateLayout . updateVisibility) wt
  where
    go _ Null = return Null
    go vmap (Fork u a mc o) = do
      u' <- go vmap u
      a' <- if ctx^.ctxNeedsRender
              then do
                SDL.destroyTexture $ ctx^.ctxTexture
                renderOnTexture vmap a
              else return a
      mc' <- case mc of
        Nothing -> return Nothing
        Just c -> do
          let (V2 w h) = fromIntegral <$> (a'^._1 . ctxWidgetState . wstSize)
              vmap' = M.insert keyWidth w . M.insert keyHeight h $ vmap -- Update width and height
          Just <$> go vmap' c
      o' <- go vmap o
      return $ Fork u' a' mc' o'
      where
        ctx = a^._1

    renderOnTexture vmap (ctx, widget) = do
      let vmap' = M.map fromIntegral vmap
      pos <- case evalExp2 vmap' upos of
              Left err -> E.throw $ userError err
              Right v  -> return $ P v
      size <- case evalExp2 vmap' usize of
              Left err -> E.throw $ userError err
              Right v  -> return v
      tex <- createTexture' size ctx widget renderWidget
      let ctx' = ctx & ctxNeedsRender .~ False
                     & ctxTexture .~ tex
                     & ctxWidgetState . wstPos .~ pos
                     & ctxWidgetState . wstSize .~ size
      return (ctx', widget)
      where
        upos = ctx^.ctxUPos
        usize = ctx^.ctxUSize


    evalExp2 :: M.Map String Double -> V2 Exp -> Either String (V2 CInt)
    evalExp2 vmap (V2 x y) = V2 <$> evalExp x <*> evalExp y
      where
        evalExp (ERPN expr) = truncate <$> RPN.eval vmap expr
        evalExp (EConst v)  = return v

    createTexture' size ctx w renderW =
      withRenderer $ \r -> do
        tex <- SDL.createTexture r SDL.RGBA8888 SDL.TextureAccessTarget size
        SDL.textureBlendMode tex $= SDL.BlendAlphaBlend
        E.bracket_ (SDL.rendererRenderTarget r $= Just tex)
                   (SDL.rendererRenderTarget r $= Nothing)
                   (renderContents r)
        return tex
      where
        wcol = optimumColor ctx
        renderContents r = do
          -- Initialize background
          SDL.rendererDrawColor r $= V4 0 0 0 0
          SDL.clear r
          -- Render contents
          renderW r size wcol w

render :: (RenderEnv m, MonadIO m) => GUI -> m ()
render = mapM_ go . view (unGui._2.gstWTree)
  where
    go (ctx,_)
      | ctx^.ctxNeedsRender            = E.throw $ userError "Call GUI.readyRender before GUI.render!"
      | ctx^.ctxWidgetState.wstVisible = renderTexture (ctx^.ctxTexture) rect
      | otherwise                      = return ()
        where
          rect = Rectangle pos size
          pos = ctx^.ctxWidgetState.wstGlobalPos
          size = ctx^.ctxWidgetState^.wstSize
