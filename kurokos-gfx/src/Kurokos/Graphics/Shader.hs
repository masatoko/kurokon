module Kurokos.Graphics.Shader where

import qualified Data.Vector.Storable          as V
-- import           Foreign.C.Types               (CInt)
-- import           Foreign.Storable              (sizeOf)
import           Linear

import qualified Graphics.GLUtil               as GLU
import qualified Graphics.GLUtil.BufferObjects as BO
import           Graphics.Rendering.OpenGL     (get, ($=))
import qualified Graphics.Rendering.OpenGL     as GL

import           Kurokos.Graphics.Types

-- Update Uniform
setUniformFloat :: UniformVar TagFloat -> GL.GLfloat -> IO ()
setUniformFloat (UniformVar TagFloat loc) mat =
  GLU.asUniform mat loc

setUniformMat4 :: UniformVar TagMat4 -> M44 GL.GLfloat -> IO ()
setUniformMat4 (UniformVar TagMat4 loc) mat =
  GLU.asUniform mat loc

setUniformMat3 :: UniformVar TagMat3 -> M33 GL.GLfloat -> IO ()
setUniformMat3 (UniformVar TagMat3 loc) mat =
  GLU.asUniform mat loc

setUniformVec3 :: UniformVar TagVec3 -> V3 GL.GLfloat -> IO ()
setUniformVec3 (UniformVar TagVec3 loc) vec =
  GLU.asUniform vec loc

setUniformVec4 :: UniformVar TagVec4 -> V4 GL.GLfloat -> IO ()
setUniformVec4 (UniformVar TagVec4 loc) vec =
  GLU.asUniform vec loc

setUniformSampler2D :: UniformVar TagSampler2D -> GL.TextureObject -> IO ()
setUniformSampler2D (UniformVar (TagSampler2D num) loc) tex = do
  GL.textureBinding GL.Texture2D $= Just tex -- glBindTexture
  GLU.asUniform (GL.TextureUnit num) loc -- TODO: Move to setup

-- Setup
setupVec2 :: AttribVar TagVec2 -> V.Vector GL.GLfloat -> IO (TypedBufferObject TagVec2)
setupVec2 (AttribVar TagVec2 loc) ps = do
  buf <- BO.fromVector GL.ArrayBuffer ps
  GL.bindBuffer GL.ArrayBuffer $= Just buf
  GL.vertexAttribPointer loc $= (GL.ToFloat, vad)
  GL.vertexAttribArray loc $= GL.Enabled
  return $ TBO buf
  where
    stride = 0
    -- stride =  fromIntegral $ sizeOf (undefined :: GL.GLfloat) * 2
    vad = GL.VertexArrayDescriptor 2 GL.Float stride GLU.offset0

setupVec3 :: AttribVar TagVec3 -> V.Vector GL.GLfloat -> IO (TypedBufferObject TagVec3)
setupVec3 (AttribVar TagVec3 loc) ps = do
  buf <- BO.fromVector GL.ArrayBuffer ps
  GL.bindBuffer GL.ArrayBuffer $= Just buf
  GL.vertexAttribPointer loc $= (GL.ToFloat, vad)
  GL.vertexAttribArray loc $= GL.Enabled
  return $ TBO buf
  where
    stride = 0
    vad = GL.VertexArrayDescriptor 3 GL.Float stride GLU.offset0

setupSampler2D :: UniformVar TagSampler2D -> IO ()
setupSampler2D (UniformVar (TagSampler2D num) _loc) =
  GL.activeTexture $= GL.TextureUnit num

-- Shader class
class Shader a where
  shdrProgram    :: a -> GL.Program
  shdrModelView  :: a -> UniformVar TagMat4
  shdrProjection :: a -> UniformVar TagMat4

class TextureShader a where
  shdrVAO          :: a -> GL.VertexArrayObject
  shdrTexCoordVbo  :: a -> TypedBufferObject TagVec2
  shdrTexCoordAttr :: a -> AttribVar TagVec2
  shdrSampler2D    :: a -> UniformVar TagSampler2D

class ColorShader a where
  shdrColor :: a -> UniformVar TagVec4

-- | Update projection matrix of BasicShader
-- setProjection :: Shader a => a -> ProjectionType -> V2 CInt -> Bool -> IO ()
-- setProjection shdr ptype (V2 winW winH) vertFlip =
--   withProgram (shdrProgram shdr) $
--     setUniformMat4 (shdrProjection shdr) $ projMat ptype
--   where
--     w = fromIntegral winW
--     h = fromIntegral winH
--     projMat Ortho =
--       if vertFlip
--         then ortho 0 w (-h) 0 (-1) 1
--         else ortho 0 w 0    h 1    (-1)
--     projMat (Frustum near far) = frustum 0 w 0 h near far

setProjection :: Shader a => a -> M44 Float -> IO ()
setProjection shdr mat =
  withProgram (shdrProgram shdr) $
    setUniformMat4 (shdrProjection shdr) mat

setTexture :: (Shader a, TextureShader a) => a -> GL.TextureObject -> IO ()
setTexture shdr tex =
  withProgram (shdrProgram shdr) $
    setUniformSampler2D (shdrSampler2D shdr) tex

setColor :: (ColorShader a, Shader a) => a -> V4 Float -> IO ()
setColor shdr color =
  withProgram (shdrProgram shdr) $
    setUniformVec4 (shdrColor shdr) color

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
