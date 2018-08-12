{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE LambdaCase       #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Git.Plantation.Cmd.Repo where

import           RIO
import qualified RIO.List               as L
import qualified RIO.Text               as Text

import           Data.Extensible
import           Git.Cmd
import           Git.Plantation.Env     (Plant)
import           Git.Plantation.Problem (Problem)
import           Git.Plantation.Team    (Team)
import           GitHub.Data.Name       (mkName)
import           GitHub.Data.Repos      (newRepo)
import           GitHub.Endpoints.Repos (Auth (..))
import qualified GitHub.Endpoints.Repos as GitHub
import           Shelly                 hiding (FilePath, unlessM)

type NewRepoCmd = Record
  '[ "repo"    >: Maybe Text
   , "team"    >: Text
   ]

createRepo :: Team -> Problem -> Plant ()
createRepo team problem = do
  logInfo $ mconcat
    [ "create repo: "
    , displayShow $ problem ^. #repo_name
    , " to team: "
    , displayShow $ team ^. #name
    ]
  updateWorkRepo problem
  (owner, repo) <- createRepoInGitHub team problem
  setRemoteRepo (owner, repo) problem
  pushBranchs (owner, repo) problem

createRepoByRepoName :: Team -> Text -> Plant ()
createRepoByRepoName team repoName = do
  conf <- asks (view #config)
  let problem = L.find (\p -> p ^. #repo_name == repoName) $ conf ^. #problems
  case problem of
    Nothing       -> logError $ "repo is not found: " <> display repoName
    Just problem' -> createRepo team problem'

createRepoInGitHub :: Team -> Problem -> Plant (Text, Text)
createRepoInGitHub team problem = do
  token <- asks (view #token)
  let (_, repo) = splitRepoName $ problem ^. #repo_name
  logInfo $ "create repo in github: " <> displayShow (problem ^. #repo_name)
  resp <- liftIO $ GitHub.createOrganizationRepo'
    (OAuth token)
    (mkName Proxy $ team ^. #github)
    (newRepo $ mkName Proxy repo)
  case resp of
    Left err -> logError "Error: create github repo" >> fail (show err)
    Right _  -> pure (team ^. #github, repo)

updateWorkRepo :: Problem -> Plant ()
updateWorkRepo problem = do
  token <- getTextToken
  workDir <- asks (view #work)
  let (owner, repo) = splitRepoName $ problem ^. #repo_name
      originUrl = mconcat ["https://", token, "@github.com/", owner, "/", repo, ".git"]
  unlessM (isExistRepoInWorkDir workDir owner repo) $ do
    logInfo $ "repository is not exist in work dir."
    shelly $ chdir_p (workDir </> owner) (clone [originUrl, repo])
  shelly $ chdir_p (workDir </> owner </> repo) (fetch [])

setRemoteRepo :: (Text, Text) -> Problem -> Plant ()
setRemoteRepo (_owner, _repo) _problem = undefined

pushBranchs :: (Text, Text) -> Problem -> Plant ()
pushBranchs (_owner, _repo) _problem = undefined

splitRepoName :: Text -> (Text, Text)
splitRepoName = fmap (Text.drop 1) . Text.span(/= '/')

isExistRepoInWorkDir :: MonadIO m => FilePath -> Text -> Text -> m Bool
isExistRepoInWorkDir workDir owner repo =
  shelly $ test_d (workDir </> Text.unpack owner </> Text.unpack repo)

getTextToken :: Plant Text
getTextToken =
  Text.decodeUtf8' <$> asks (view #token) >>= \case
    Left  _ -> logError "cannot decode token to utf8." >> pure ""
    Right t -> pure t
