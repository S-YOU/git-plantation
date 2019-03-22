{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedLabels      #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Main where

import qualified Paths_git_plantation as Meta
import           RIO

import           Configuration.Dotenv (defaultConfig, loadFile)
import           Data.Extensible
import           Data.Version         (Version)
import qualified Data.Version         as Version
import           Development.GitRev
import           GHC.TypeLits
import           Git.Plantation.Cmd
import           Options.Applicative

main :: IO ()
main = do
  _ <- tryIO $ loadFile defaultConfig
  run =<< execParser opts
  where
    opts = info (options <**> version Meta.version <**> helper)
         $ fullDesc
        <> header "taskpad - operate daily tasks"

options :: Parser Options
options = hsequence
    $ #verbose <@=> switch (long "verbose" <> short 'v' <> help "Enable verbose mode: verbosity level \"debug\"")
   <: #config  <@=> strOption (long "config" <> short 'c' <> value "config.yaml" <> metavar "PATH" <> help "Configuration file")
   <: #work    <@=> strOption (long "work" <> value "~/.git-plantation" <> metavar "PATH" <> help "Work directory to exec git commands")
   <: #subcmd  <@=> subcmdParser
   <: nil

subcmdParser :: Parser SubCmd
subcmdParser = variantFrom
    $ #verify           @= pure ()               `withInfo` "Verify config file."
   <: #new_repo         @= newRepoCmdParser      `withInfo` "Create repository for team."
   <: #new_github_repo  @= singleRepoCmdParser   `withInfo` "Create new repository for team in GitHub"
   <: #init_github_repo @= singleRepoCmdParser   `withInfo` "Init repository for team in GitHub"
   <: #init_ci          @= singleRepoCmdParser   `withInfo` "Init CI repository by team repository"
   <: #reset_repo       @= singleRepoCmdParser   `withInfo` "Reset repository for team"
   <: #delete_repo      @= deleteRepoCmdParser   `withInfo` "Delete repository for team."
   <: #invite_member    @= inviteMemberCmdParser `withInfo` "Invite Member to Team Repository"
   <: nil

newRepoCmdParser :: Parser NewRepoCmd
newRepoCmdParser = hsequence
    $ #repo <@=> option (Just <$> str) (long "repo" <> value Nothing <> metavar "TEXT" <> help "Sets reopsitory that wont to controll.")
   <: #team <@=> strArgument (metavar "TEXT" <> help "Sets team that wont to controll.")
   <: nil

singleRepoCmdParser :: Parser (Record RepoCmdFields)
singleRepoCmdParser = hsequence
    $ #repo <@=> strOption (long "repo" <> metavar "TEXT" <> help "Sets reopsitory that wont to controll.")
   <: #team <@=> strArgument (metavar "TEXT" <> help "Sets team that wont to controll.")
   <: nil

deleteRepoCmdParser :: Parser DeleteRepoCmd
deleteRepoCmdParser = newRepoCmdParser

inviteMemberCmdParser :: Parser InviteMemberCmd
inviteMemberCmdParser = hsequence
    $ #team <@=> strArgument (metavar "TEXT" <> help "Sets team that wont to controll.")
   <: #repo <@=> option (Just <$> auto) (long "repo" <> value Nothing <> metavar "ID" <> help "Sets reopsitory by problem id that wont to controll.")
   <: #user <@=> option (Just <$> str) (long "user" <> value Nothing <> metavar "TEXT" <> help "Sets user that wont to controll.")
   <: nil

variantFrom ::
  Forall (KeyIs KnownSymbol) xs => RecordOf ParserInfo xs -> Parser (Variant xs)
variantFrom = subparser . subcmdVariant
  where
    subcmdVariant = hfoldMapWithIndexFor (Proxy @ (KeyIs KnownSymbol)) $ \m x ->
      let k = symbolVal (proxyAssocKey m)
      in command k ((EmbedAt m . Field . pure) <$> getField x)

instance Wrapper ParserInfo where
  type Repr ParserInfo a = ParserInfo a
  _Wrapper = id

withInfo :: Parser a -> String -> ParserInfo a
withInfo opts = info (helper <*> opts) . progDesc

version :: Version -> Parser (a -> a)
version v = infoOption (showVersion v)
    $ long "version"
   <> help "Show version"

showVersion :: Version -> String
showVersion v = unwords
  [ "Version"
  , Version.showVersion v ++ ","
  , "Git revision"
  , $(gitHash)
  , "(" ++ $(gitCommitCount) ++ " commits)"
  ]