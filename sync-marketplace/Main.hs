module Main
    ( main
    ) where

import Restyled.Prelude

import LoadEnv (loadEnvFrom)
import Restyled.Options
import Restyled.SyncMarketplace

main :: IO ()
main = do
    setLineBuffering
    RestyledOptions {..} <- parseRestyledOptions
    traverse_ loadEnvFrom oEnvFile
    app <- loadApp
    runRIO app syncMarketplace
