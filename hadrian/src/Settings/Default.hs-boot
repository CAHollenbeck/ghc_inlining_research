module Settings.Default (
    SourceArgs (..), sourceArgs, defaultBuilderArgs, defaultPackageArgs,
    defaultExtraArgs, defaultHaddockExtraArgs, defaultLibraryWays, defaultRtsWays,
    defaultFlavour, defaultBignumBackend
    ) where

import Flavour.Type
import Expression

data SourceArgs = SourceArgs
    { hsDefault  :: Args
    , hsLibrary  :: Args
    , hsCompiler :: Args
    , hsGhc      :: Args }

sourceArgs :: SourceArgs -> Args

defaultBuilderArgs, defaultPackageArgs, defaultExtraArgs, defaultHaddockExtraArgs :: Args
defaultLibraryWays, defaultRtsWays :: Ways
defaultFlavour :: Flavour
defaultBignumBackend :: String
