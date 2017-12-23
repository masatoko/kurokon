{-# LANGUAGE RecordWildCards #-}
module Kurokos.Renderer
  ( Renderer (rndrPrimShader)
  , getFreeType
  , newRenderer
  , freeRenderer
  --
  , renderTexture
  , renderText
  ) where

import           Foreign.C.Types                              (CInt)
import           Graphics.Rendering.FreeType.Internal.Library (FT_Library)
import           Linear.V2

import qualified Kurokos.Graphics.Camera                      as Cam
import           Kurokos.Graphics.Font                        (doneFreeType,
                                                               initFreeType)
import qualified Kurokos.Graphics.Render                      as Render
import           Kurokos.Graphics.Shader                      (setProjection,
                                                               setTexture)
import qualified Kurokos.Graphics.Shader.Basic                as Basic
import qualified Kurokos.Graphics.Shader.Primitive            as Prim
import qualified Kurokos.Graphics.Shader.Text                 as Text
import           Kurokos.Graphics.Types                       (CharTexture, ProjectionType (..),
                                                               RContext (..),
                                                               Texture (..))

data Renderer = Renderer
  { rndrBasicShader :: Basic.BasicShader
  , rndrPrimShader  :: Prim.PrimitiveShader
  , rndrTextShader  :: Text.TextShader
  , rndrFreeType    :: FT_Library
  }

getFreeType :: Renderer -> FT_Library
getFreeType = rndrFreeType

newRenderer :: V2 CInt -> IO Renderer
newRenderer winSize = do
  b <- Basic.newBasicShader
  setProjection b Ortho winSize' True
  p <- Prim.newPrimitiveShader
  setProjection p Ortho winSize' True
  t <- Text.newTextShader
  setProjection t Ortho winSize' True
  ft <- initFreeType
  return $ Renderer b p t ft
  where
    winSize' = fromIntegral <$> winSize

freeRenderer :: Renderer -> IO ()
freeRenderer Renderer{..} =
  doneFreeType rndrFreeType
  -- TODO: Implement others

-- | Render Texture with camera.
renderTexture :: Renderer -> Texture -> RContext -> IO ()
renderTexture Renderer{..} tex rctx = do
  setTexture rndrBasicShader $ texObject tex
  let mv = Render.mkModelViewForNormalized Cam.camForVertFlip rctx
  Render.setModelView rndrBasicShader mv
  Render.renderTextureShader rndrBasicShader

-- | Render CharTexture list.
renderText :: Foldable t => Renderer -> V2 Int -> t CharTexture -> IO ()
renderText Renderer{..} =
  Render.renderTextTexture rndrTextShader
