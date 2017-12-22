{-# LANGUAGE RecordWildCards #-}
module Kurokos.Graphics.Shader where

import           Data.Maybe                (fromMaybe)
import           Foreign.C.Types           (CInt)
import           Foreign.Storable          (sizeOf)
import           Linear

import qualified Graphics.GLUtil           as GLU
import           Graphics.Rendering.OpenGL (get, ($=))
import qualified Graphics.Rendering.OpenGL as GL

import qualified Kurokos.Graphics.Camera   as Cam
import           Kurokos.Graphics.Texture  (Texture (..))
import           Kurokos.Graphics.Types

-- | Rendering context
data RContext = RContext
  { rctxCoord     :: V2 Float
  -- ^ Left bottom coord
  , rctxSize      :: Maybe (V2 Float)
  -- ^ Size
  , rctxRot       :: Maybe Float
  -- ^ Rotation angle [rad]
  , rctxRotCenter :: Maybe (V2 Float)
  -- ^ Rotation center coord
  }


data ProjectionType
  = Ortho
  | Frustum Float Float -- Near Far
  deriving (Eq, Show)

-- Update Uniform
setUniformMat4 :: UniformVar TagMat4 -> M44 GL.GLfloat -> IO ()
setUniformMat4 (UniformVar TagMat4 loc) mat =
  GLU.asUniform mat loc

setUniformVec3 :: UniformVar TagVec3 -> V3 GL.GLfloat -> IO ()
setUniformVec3 (UniformVar TagVec3 loc) vec =
  GLU.asUniform vec loc

setUniformSampler2D :: UniformVar TagSampler2D -> GL.TextureObject -> IO ()
setUniformSampler2D (UniformVar (TagSampler2D num) loc) tex = do
  GL.textureBinding GL.Texture2D $= Just tex -- glBindTexture
  GLU.asUniform (GL.TextureUnit num) loc -- TODO: Move to setup

-- Setup
setupVec2 :: AttribVar TagVec2 -> [GL.GLfloat] -> IO ()
setupVec2 (AttribVar TagVec2 loc) ps = do
  buf <- GLU.makeBuffer GL.ArrayBuffer ps
  GL.bindBuffer GL.ArrayBuffer $= Just buf
  GL.vertexAttribPointer loc $= (GL.ToFloat, vad)
  GL.vertexAttribArray loc $= GL.Enabled
  where
    stride =  fromIntegral $ sizeOf (undefined :: GL.GLfloat) * 2
    vad = GL.VertexArrayDescriptor 2 GL.Float stride GLU.offset0

setupSampler2D :: UniformVar TagSampler2D -> IO ()
setupSampler2D (UniformVar (TagSampler2D num) loc) =
  GL.activeTexture $= GL.TextureUnit num

-- Util
withProgram :: GL.Program -> IO a -> IO a
withProgram p act = do
  cur <- get GL.currentProgram
  if cur == Just p
    then act
    else do
      GL.currentProgram $= Just p
      ret <- act
      GL.currentProgram $= cur
      return ret
