{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
module Main where

import qualified Control.Exception             as E
import           Control.Monad                 (unless)
import           Control.Monad.IO.Class        (liftIO)
import           Control.Monad.Managed         (managed, runManaged)
import           Linear.V2
import           Linear.V4

import qualified SDL
import           SDL.Event

import qualified Graphics.GLUtil               as GLU
import           Graphics.Rendering.OpenGL     (get, ($=))
import qualified Graphics.Rendering.OpenGL     as GL

import qualified Kurokos.Graphics              as G
-- import qualified Kurokos.Graphics.Camera       as Cam
import qualified Kurokos.Graphics.Font         as Font

main :: IO ()
main = do
  SDL.initializeAll
  window <- SDL.createWindow "Test kurokos-gfx" winConf
  withGL window $ \_glContext -> do
    winSize@(V2 winW winH) <- get $ SDL.windowSize window
    GL.viewport $= (GL.Position 0 0, GL.Size (fromIntegral winW) (fromIntegral winH))
    SDL.swapInterval $= SDL.SynchronizedUpdates
    GL.clearColor $= GL.Color4 0.2 0.2 0.2 1
    --
    runManaged $ do
      ft <- managed Font.withFreeType
      face <- managed $ E.bracket (Font.newFace ft "_test/mplus-1p-medium.ttf") Font.doneFace
      liftIO $ Font.setPixelSize face 32
      --
      text1 <- managed $
                E.bracket (G.createTextTexture face (V4 255 0 0 255) "Hello, ") G.deleteTextTexture
      text2 <- managed $
                E.bracket (G.createTextTexture face (V4 0 0 255 255) "World!") G.deleteTextTexture
      let texttex = text1 ++ text2

      liftIO $ do
        rndr <- G.newRenderer winSize
        tex1 <- G.readTexture "_data/in_transit.png"
        tex2 <- G.readTexture "_data/panorama.png"
        let ps = map (uncurry V2) [(0,0), (100,0), (50,100)]
        poly <- G.newPrim rndr GL.LineLoop ps
        loop window rndr tex1 tex2 texttex poly
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

    loop win rndr tex1 tex2 texttex poly = go (0 :: Integer)
      where
        go i = do
          let i' = fromIntegral i
          GLU.printError
          events <- SDL.pollEvent
          GL.clear [GL.ColorBuffer]
          --
          let ctx = G.RContext (pure 0) (pure i') Nothing Nothing
              tex = if i `mod` 60 < 30 then tex1 else tex2
          G.renderTexture rndr tex ctx
          --
          G.renderText rndr (V2 100 240) texttex
          --
          G.drawPrim rndr (V2 400 200) poly
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
