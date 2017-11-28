module Main where

import           Control.Monad (forever)
import qualified Data.Map      as M

import           Kurokos.RPN

main :: IO ()
main = do
  putStrLn "constant values"
  mapM_ work $ M.toList vmap
  --
  forever $ do
    eExpr <- parse <$> getLine
    case eExpr of
      Left err   -> putStrLn err
      Right expr -> print $ eval vmap expr
  where
    vmap = M.fromList [("x", 10), ("y", 20)]

    work (key, value) =
      putStrLn $ "- $" ++ key ++ " = " ++ show value
