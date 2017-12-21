{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
module Main where

import qualified Control.Exception         as E
import           Control.Monad             (unless)
import           Data.Either.Extra         (fromRight)
import           Foreign.Storable          (sizeOf)
import           Linear.V2
import           System.FilePath.Posix

import qualified SDL
import           SDL.Event

import qualified Graphics.GL               as GLRaw
import qualified Graphics.GLUtil           as GLU
import           Graphics.Rendering.OpenGL (get, ($=))
import qualified Graphics.Rendering.OpenGL as GL

import qualified Kurokos.Graphics.Font     as Font
import qualified Kurokos.Graphics.Shader   as KG
import qualified Kurokos.Graphics.Texture  as KG
import qualified Kurokos.Graphics.Texture

main :: IO ()
main = do
  SDL.initializeAll
  window <- SDL.createWindow "Test kurokos-gfx" winConf
  withGL window $ \glContext -> do
    -- GL.viewport $= (GL.Position 0 0, GL.Size (fromIntegral w) (fromIntegral h))
    SDL.swapInterval $= SDL.SynchronizedUpdates
    GL.clearColor $= GL.Color4 0 1 0 1
    --
    charTexObj <- Font.loadCharacter "_test/mplus-1p-medium.ttf" 'A' 128
    let charTex = Kurokos.Graphics.Texture.Texture charTexObj 128 128

    br <- KG.newBasicRenderer
    winSize <- get $ SDL.windowSize window
    KG.updateBasicRenderer KG.Ortho winSize br
    --
    Right tex1 <- KG.readTexture "_data/in_transit.png"
    Right tex2 <- KG.readTexture "_data/panorama.png"
    loop window br charTex tex2
  where
    winConf =
      SDL.defaultWindow
        { SDL.windowOpenGL = Just glConf
        , SDL.windowInitialSize = V2 640 480}

    withGL win =
      E.bracket (SDL.glCreateContext win)
                SDL.glDeleteContext

    glConf =
      SDL.defaultOpenGL
        { SDL.glProfile = SDL.Core SDL.Debug 4 0
        }

    loop win br tex1 tex2 = go 0
      where
        go i = do
          GLU.printError
          events <- SDL.pollEvent
          GL.clear [GL.ColorBuffer]
          --
          let ctx = KG.RContext (V2 320 240) (Just (pure $ fromIntegral i)) (Just $ fromIntegral i / 10) Nothing
          KG.renderTexByBasicRenderer_ br ctx $ if i `mod` 60 < 30 then tex1 else tex2
          --
          SDL.glSwapWindow win
          unless (any shouldExit events) $ go (i + 1)

    shouldExit e =
      case SDL.eventPayload e of
        KeyboardEvent KeyboardEventData{..} ->
          keyboardEventKeyMotion == Pressed
            && SDL.keysymKeycode keyboardEventKeysym `elem` [SDL.KeycodeQ, SDL.KeycodeEscape]
        WindowClosedEvent WindowClosedEventData{} -> True
        _ -> False
