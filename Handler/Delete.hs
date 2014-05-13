{-# LANGUAGE TupleSections, OverloadedStrings #-}
module Handler.Delete where

import           Import
import qualified Prelude            as P (head, tail)
import           Yesod.Auth
import qualified Database.Esqueleto as E
import qualified Data.Text          as T
import qualified Data.Map.Strict    as Map
import           System.Directory   (removeFile)
import           Handler.EventSource (sendDeletedPosts)
---------------------------------------------------------------------------------------------
getDeletedByOpR :: Text -> Int -> Handler Html
getDeletedByOpR board thread = do
  when (thread == 0) notFound
  muser    <- maybeAuth
  mgroup   <- getMaybeGroup muser
  boardVal <- getBoardVal404 board
  checkViewAccess mgroup boardVal
  let permissions   = getPermissions       mgroup
      geoIpEnabled  = boardEnableGeoIp     boardVal
      boardDesc     = boardDescription     boardVal
      boardLongDesc = boardLongDescription boardVal
      showPostDate  = boardShowPostDate    boardVal
      showEditHistory  = boardShowEditHistory boardVal
  unless (boardOpModeration boardVal) notFound  
  -------------------------------------------------------------------------------------------------------
  allPosts' <- runDB $ E.select $ E.from $ \(post `E.LeftOuterJoin` file) -> do
    E.on $ (E.just (post E.^. PostId)) E.==. (file E.?. AttachedfileParentId)
    E.where_ ((post E.^. PostBoard       ) E.==. (E.val board ) E.&&.
              (post E.^. PostDeletedByOp ) E.==. (E.val True  ) E.&&.
              (post E.^. PostParent      ) E.==. (E.val thread))
    E.orderBy [E.asc (post E.^. PostId)]
    return (post, file)
  let allPosts = map (second catMaybes) $ Map.toList $ keyValuesToMap allPosts'
  ------------------------------------------------------------------------------------------------------- 
  geoIps <- getCountries (if geoIpEnabled then allPosts else [])      
  ------------------------------------------------------------------------------------------------------- 
  nameOfTheBoard <- extraSiteName <$> getExtra
  msgrender      <- getMessageRender
  timeZone       <- getTimeZone
  rating         <- getCensorshipRating
  displaySage    <- getConfig configDisplaySage
  maxLenOfFileName <- extraMaxLenOfFileName <$> getExtra
  defaultLayout $ do
    setUltDestCurrent
    setTitle $ toHtml $ nameOfTheBoard <> titleDelimiter <> msgrender MsgDeletedPosts
    $(widgetFile "deleted")

getDeleteR :: Handler Html
getDeleteR = do
  query  <- reqGetParams <$> getRequest
  muser  <- maybeAuth
  mgroup <- getMaybeGroup muser
  let errorRedirect msg = setMessageI msg >> redirectUltDest HomeR
      nopasreq          = maybe False ((DeletePostsP `elem`) . groupPermissions . entityVal) mgroup
      helper x          = toKey ((read $ unpack $ snd x) :: Int )
  case reverse query of
    ("postpassword",pswd):("opmoderation",threadId):zs | null zs   -> errorRedirect MsgDeleteNoPosts
                                                       | otherwise -> do
      let xs = if fst (P.head zs) == "onlyfiles" then P.tail zs else zs
      thread   <- runDB $ get ((toKey ((read $ unpack threadId) :: Int)) :: Key Post)
      when (isNothing thread) notFound

      let board = postBoard $ fromJust thread
      boardVal    <- getBoardVal404 board
      unless (boardOpModeration boardVal) notFound

      posterId <- getPosterId
      when (postPosterId (fromJust thread) /= posterId &&
            postPassword (fromJust thread) /= pswd
           ) $ errorRedirect MsgYouAreNotOp
      let requestIds = map helper xs
          myFilterPr (Entity _ p) = postBoard       p == board &&
                                    postParent      p == postLocalId (fromJust thread) &&
                                    postDeletedByOp p == False
      posts <- filter myFilterPr <$> runDB (selectList [PostId <-. requestIds] [])
      case posts of
        [] -> errorRedirect MsgDeleteNoPosts
        _  -> sendDeletedPosts (map entityVal posts) >> deletePostsByOp posts >> redirectUltDest HomeR

    ("postpassword",pswd):zs | null zs   -> errorRedirect MsgDeleteNoPosts
                             | otherwise -> do
      let onlyfiles    = fst (P.head zs) == "onlyfiles"
          xs           = if onlyfiles then P.tail zs else zs
          requestIds   = map helper xs
          myFilterPr e = nopasreq || (postPassword (entityVal e) == pswd)
      posts <- filter myFilterPr <$> runDB (selectList [PostId <-. requestIds] [])
      case posts of
        [] -> errorRedirect MsgDeleteWrongPassword
        _  -> unless onlyfiles (sendDeletedPosts $ map entityVal posts) >> deletePosts posts onlyfiles >> redirectUltDest HomeR
    _                           -> errorRedirect MsgUnknownError

---------------------------------------------------------------------------------------------
deleteFiles :: [Key Post] -> Handler ()
deleteFiles idsToRemove = do
  files <- runDB $ selectList [AttachedfileParentId <-. idsToRemove] []
  forM_ files $ \(Entity fId f) -> do
    sameFilesCount <- runDB $ count [AttachedfileMd5 ==. attachedfileMd5 f, AttachedfileId !=. fId]
    case sameFilesCount `compare` 0 of
      GT -> do -- this file belongs to several posts so don't delete it from disk
        filesWithSameThumbSize <- runDB $ count [AttachedfileThumbSize ==. attachedfileThumbSize f, AttachedfileId !=. fId]
        unless (filesWithSameThumbSize > 0) $
          when (isImageFile $ attachedfileType f) $
            void $ liftIO $ removeFile $ thumbFilePath (attachedfileThumbSize f) (attachedfileType f) (attachedfileName f)
      _  -> do
        let t = attachedfileType f
        liftIO $ removeFile $ imageFilePath t $ attachedfileName f
        when (isImageFile t) $ 
          liftIO $ removeFile $ thumbFilePath (attachedfileThumbSize f) t $ attachedfileName f
  runDB $ deleteWhere [AttachedfileParentId <-. idsToRemove]
---------------------------------------------------------------------------------------------
-- used by Handler/Admin and Handler/Board
---------------------------------------------------------------------------------------------
deletePostsByOp :: [Entity Post] -> Handler ()
deletePostsByOp = runDB . mapM_ (\(Entity pId _) -> update pId [PostDeletedByOp =. True])

deletePosts :: [Entity Post] -> Bool -> Handler ()
deletePosts posts onlyfiles = do
  let boards         = nub $ map (postBoard . entityVal) posts
      boardsAndPosts = map (\b -> (b, filter ((==b) . postBoard . entityVal) posts)) boards
      boardsAndPosts :: [(Text,[Entity Post])]

  childs <- runDB $ forM boardsAndPosts $ \(b,ps) ->
    selectList [PostBoard ==. b, PostParent <-. map (postLocalId . entityVal) ps] []

  let idsToRemove = concat (map (map entityKey . snd) boardsAndPosts) ++ map entityKey (concat childs)
  unless onlyfiles $
    runDB (updateWhere [PostId <-. idsToRemove] [PostDeleted =. True])
  deleteFiles idsToRemove
