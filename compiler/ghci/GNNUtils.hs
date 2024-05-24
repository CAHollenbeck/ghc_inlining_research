{-# LANGUAGE DeriveGeneric #-}

module GNNUtils (
  Predictions(..),
  getPredsFromFlag,
  inPredictions 
) where

import FastString
import System.IO.Unsafe (unsafePerformIO)
import GHC.Generics (Generic)
import Data.ByteString.Lazy as L (readFile)
import qualified Data.Binary as B
import Prelude

import Debug.Trace (trace)


data FileObject = FileObject {
      filename    :: String,    -- the file name
      funnames    :: [String]   -- the functions in the file to receive a pragma
} deriving (Show, Generic)

-- helper: Checks if the function name is in the list of functions to inline
isElem :: String -> [String] -> Bool
isElem fun [] = False
isElem fun (fn:fns) = if fun == fn
                         then True
                         else isElem fun fns

removeQuotes :: String -> String
removeQuotes xs = [ x | x <- xs, not (x == '\"') ]

-- Checks if the function name is in the list of functions to inline
inPredictions :: String -> String -> [FileObject] -> Bool
inPredictions fname func fos = inPredictions' fname_ func_ fos
    where fname_ = removeQuotes fname
          func_  = removeQuotes func

-- helper: Checks if the function name is in the list of functions to inline
inPredictions' :: String -> String -> [FileObject] -> Bool
inPredictions' fname func [] = False
inPredictions' fname func (fo:fos) = if fname == (filename fo)
                                          then isElem func (funnames fo)
                                          else inPredictions' fname func fos 

data Predictions = Predictions {
     fileobjects :: [FileObject]
} deriving (Show, Generic)

instance B.Binary FileObject where
  get = do
          fn  <- B.get
          fns <- B.get
          return (FileObject {
                    filename = fn,
                    funnames = fns
                 })

instance B.Binary Predictions where
  get = do
         fos <- B.get
         return (Predictions {
                      fileobjects = fos
                 })

-- Read the recommendations file from the file passed in the flag
getPredsFromFlag :: String -> Maybe Predictions
getPredsFromFlag s = Just (B.decode (unsafePerformIO (L.readFile s)) :: Predictions)
