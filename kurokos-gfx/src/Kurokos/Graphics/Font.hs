module Kurokos.Graphics.Font where

import qualified Control.Exception                                   as E
import           Control.Monad                                       (foldM,
                                                                      foldM_,
                                                                      forM,
                                                                      unless)
import           Data.ByteString.Internal                            (ByteString (..))
import           Foreign.ForeignPtr                                  (withForeignPtr)
import           Foreign.Ptr                                         (plusPtr)
import           Foreign.Storable                                    (peek,
                                                                      poke)
import           GHC.ForeignPtr                                      (mallocPlainForeignPtrBytes)
import           Linear.V3                                           (V3 (..))
import           System.IO                                           (hPutStrLn,
                                                                      stderr)

import qualified Data.ByteString                                     as BS
import           Graphics.Rendering.OpenGL                           (get, ($=))
import qualified Graphics.Rendering.OpenGL                           as GL

import           Foreign                                             (Ptr,
                                                                      Word8,
                                                                      alloca,
                                                                      allocaBytes,
                                                                      realloc,
                                                                      reallocBytes,
                                                                      peekArray)
import           Foreign.C.String                                    (withCString)
import           Foreign.C.Types                                     (CChar (..), CUChar (..))
import qualified Graphics.GLUtil                                     as GLU
import qualified Graphics.Rendering.FreeType.Internal                as FT
import qualified Graphics.Rendering.FreeType.Internal.Bitmap         as FT
import qualified Graphics.Rendering.FreeType.Internal.BitmapSize     as FTS
import qualified Graphics.Rendering.FreeType.Internal.Face           as FT
import qualified Graphics.Rendering.FreeType.Internal.FaceType       as FT
import qualified Graphics.Rendering.FreeType.Internal.GlyphSlot      as FT
import qualified Graphics.Rendering.FreeType.Internal.Library        as FT
import qualified Graphics.Rendering.FreeType.Internal.PrimitiveTypes as FT

-- Reffered this article [http://zyghost.com/articles/Haskell-font-rendering-with-freetype2-and-opengl.html].
-- Original code is [https://github.com/schell/editor/blob/glyph-rendering/src/Graphics/Text/Font.hs].
-- Thanks to schell.

loadCharacter :: FilePath -> Char -> Int -> IO GL.TextureObject
loadCharacter path char px = do
  -- FreeType (http://freetype.org/freetype2/docs/tutorial/step1.html)
  ft <- initFreeType

  -- Get the Ubuntu Mono fontface.
  -- ff <- newFace ft path
  ff <- newFaceBS ft =<< BS.readFile path
  throwIfNot0 $ FT.ft_Set_Pixel_Sizes ff (fromIntegral px) 0

  -- Get the unicode char index.
  chNdx <- FT.ft_Get_Char_Index ff $ fromIntegral $ fromEnum char

  -- Load the glyph into freetype memory.
  throwIfNot0 $ FT.ft_Load_Glyph ff chNdx FT.ft_LOAD_DEFAULT

  -- Get the GlyphSlot.
  slot <- peek $ FT.glyph ff

  -- Number of glyphs
  n <- peek $ FT.num_glyphs ff
  putStrLn $ "glyphs:" ++ show n

  fmt <- peek $ FT.format slot
  putStrLn $ "glyph format:" ++ glyphFormatString fmt

  -- This is [] for Ubuntu Mono, but I'm guessing for bitmap
  -- fonts this would be populated with the different font
  -- sizes.
  putStr "Sizes:"
  numSizes <- peek $ FT.num_fixed_sizes ff
  sizesPtr <- peek $ FT.available_sizes ff
  sizes <- forM [0 .. numSizes-1] $ \i ->
      peek $ sizesPtr `plusPtr` fromIntegral i :: IO FTS.FT_Bitmap_Size
  print sizes

  l <- peek $ FT.bitmap_left slot
  t <- peek $ FT.bitmap_top slot
  putStrLn $ concat [ "left:"
                    , show l
                    , "\ntop:"
                    , show t
                    ]

  throwIfNot0 $ FT.ft_Render_Glyph slot FT.ft_RENDER_MODE_NORMAL

  -- Get the char bitmap.
  bmp <- peek $ FT.bitmap slot
  putStrLn $ concat ["width:"
                    , show $ FT.width bmp
                    , " rows:"
                    , show $ FT.rows bmp
                    , " pitch:"
                    , show $ FT.pitch bmp
                    , " num_grays:"
                    , show $ FT.num_grays bmp
                    , " pixel_mode:"
                    , show $ FT.pixel_mode bmp
                    , " palette_mode:"
                    , show $ FT.palette_mode bmp
                    ]

  let w  = fromIntegral $ FT.width bmp
      h  = fromIntegral $ FT.rows bmp
      w' = fromIntegral w :: Integer
      h' = fromIntegral h
      p  = 4 - w `mod` 4
      nw = p + fromIntegral w'

  putStrLn $ "padding by " ++ show p

  -- Get the raw bitmap data.
  bmpData <- peekArray (w*h) $ FT.buffer bmp

  let data' = addPadding p w 0 bmpData
      -- data'' = concat $ map toRGBA data'
  data'' <- makeRGBABytes (V3 255 0 255) data'

  -- Set the texture params on our bound texture.
  GL.texture GL.Texture2D $= GL.Enabled

  -- Generate an opengl texture.
  tex <- newBoundTexUnit 0
  GLU.printError
  --
  putStrLn "Buffering glyph bitmap into texture."
  let (PS fptr off len) = data''
  let pokeColor ptr _ = do
        GL.texImage2D
          GL.Texture2D
          GL.NoProxy
          0
          GL.RGBA8 -- PixelInternalFormat
          (GL.TextureSize2D (fromIntegral nw) h')
          0
          (GL.PixelData GL.RGBA GL.UnsignedByte ptr) -- PixelFormat
        return $ ptr `plusPtr` off
  withForeignPtr fptr $ \ptr0 ->
    foldM_ pokeColor ptr0 $ take len [0..]

  GLU.printError

  putStrLn "Texture loaded."
  GL.textureFilter   GL.Texture2D   $= ((GL.Linear', Nothing), GL.Linear')
  GL.textureWrapMode GL.Texture2D GL.S $= (GL.Repeated, GL.ClampToEdge)
  GL.textureWrapMode GL.Texture2D GL.T $= (GL.Repeated, GL.ClampToEdge)

  return tex

newBoundTexUnit :: Int -> IO GL.TextureObject
newBoundTexUnit u = do
  [tex] <- GL.genObjectNames 1
  GL.texture GL.Texture2D $= GL.Enabled
  GL.activeTexture $= GL.TextureUnit (fromIntegral u)
  GL.textureBinding GL.Texture2D $= Just tex
  return tex

addPadding :: Int -> Int -> a -> [a] -> [a]
addPadding _   _ _   [] = []
addPadding amt w val xs = a ++ b ++ c
  where
    a = take w xs
    b = replicate amt val
    c = addPadding amt w val (drop w xs)

makeRGBABytes :: V3 Word8 -> [CChar] -> IO BS.ByteString
makeRGBABytes (V3 r g b) cs =
  create (length cs * 4) $ \ptr0 ->
    foldM_ work ptr0 cs
  where
    work p0 (CChar a) =
      foldM poke' p0 [r,g,b, fromIntegral a]
      where
        poke' p depth = do
          poke p depth
          return $ p `plusPtr` 1

    create :: Int -> (Ptr Word8 -> IO ()) -> IO ByteString
    create l f = do
      fp <- mallocPlainForeignPtrBytes l
      withForeignPtr fp $ \p -> f p
      return $! PS fp 0 l

glyphFormatString :: FT.FT_Glyph_Format -> String
glyphFormatString fmt
  | fmt == FT.ft_GLYPH_FORMAT_COMPOSITE = "ft_GLYPH_FORMAT_COMPOSITE"
  | fmt == FT.ft_GLYPH_FORMAT_OUTLINE   = "ft_GLYPH_FORMAT_OUTLINE"
  | fmt == FT.ft_GLYPH_FORMAT_PLOTTER   = "ft_GLYPH_FORMAT_PLOTTER"
  | fmt == FT.ft_GLYPH_FORMAT_BITMAP    = "ft_GLYPH_FORMAT_BITMAP"
  | otherwise                           = "ft_GLYPH_FORMAT_NONE"

--
withFreeType :: (FT.FT_Library -> IO a) -> IO a
withFreeType = E.bracket initFreeType doneFreeType

initFreeType :: IO FT.FT_Library
initFreeType = alloca $ \p -> do
  throwIfNot0 $ FT.ft_Init_FreeType p
  peek p

doneFreeType :: FT.FT_Library -> IO ()
doneFreeType ft = throwIfNot0 $ FT.ft_Done_FreeType ft
--

--
newFace :: FT.FT_Library -> FilePath -> IO FT.FT_Face
newFace ft fp = withCString fp $ \str ->
  alloca $ \ptr -> do
    throwIfNot0 $ FT.ft_New_Face ft str 0 ptr
    peek ptr

newFaceBS :: FT.FT_Library -> BS.ByteString -> IO FT.FT_Face
newFaceBS ft bytes@(PS fptr off len) =
  -- Is there any smart way?
  allocaBytes len $ \dst0 -> do -- Destination (Ptr CUChar8)
    withForeignPtr fptr $ \org0 -> -- Origin (Ptr Word8)
      foldM_ work (org0, dst0 :: Ptr CUChar) $ take len [0..]
    alloca $ \ptr -> do
      FT.ft_New_Memory_Face ft dst0 (fromIntegral len) 0 ptr
      peek ptr
  where
    work (from, to) _ = do
      poke to . fromIntegral =<< peek from
      return (from `plusPtr` 1, to `plusPtr` 1)

doneFace :: FT.FT_Face -> IO ()
doneFace face = throwIfNot0 $ FT.ft_Done_Face face
--

throwIfNot0 :: IO FT.FT_Error -> IO ()
throwIfNot0 m = do
  r <- m
  unless (r == 0) $
    E.throwIO $ userError $ "FreeType Error:" ++ show r
