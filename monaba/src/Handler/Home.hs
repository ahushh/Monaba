module Handler.Home where

import Import
import qualified Data.Text as T (null)

getHomeR :: Handler TypedContent
getHomeR = do
  AppSettings{..} <- appSettings <$> getYesod
  group  <- (fmap $ userGroup . entityVal) <$> maybeAuth
  boards <- runDB $ selectList ([]::[Filter Board]) []
  config <- getConfigEntity
  let boardCategories = configBoardCategories config
      newsBoard       = configNewsBoard       config
      showNews        = configShowNews        config
      homeContent     = configHome            config
      lastPics        = configHomeRecentPics  config
      selectFiles p   = runDB $ selectList [AttachedfileParentId ==. entityKey p] []
      selectNews      = selectList [PostBoard ==. newsBoard, PostParent ==. 0, PostDeleted ==. False]
                                   [Desc PostLocalId, LimitTo showNews]
  newsAndFiles <- runDB selectNews >>= mapM (\p -> selectFiles p >>= (\files -> return (p, files)))
  timeZone     <- getTimeZone

  now <- liftIO getCurrentTime  
  let month = addUTCTime' (-60*60*24*30) now
      day   = addUTCTime' (-60*60*24*1 ) now
  statsAllPosts   <- runDB $ count [PostDeleted ==. False]
  statsAllDeleted <- runDB $ count [PostDeleted ==. True]
  statsMonth      <- runDB $ count [PostDate >. month, PostDeleted ==. False]
  statsDay        <- runDB $ count [PostDate >. day, PostDeleted ==. False]
  statsAllFiles   <- runDB $ count ([]::[Filter Attachedfile])

  ip              <- pack <$> getIp
  recentImages    <- runDB $ selectList ([AttachedfileFiletype ==. FileImage]++ if not (isOnion ip) then [AttachedfileOnion ==. False] else []) [Desc AttachedfileId, LimitTo lastPics]
  selectRep $ do
    provideRep $ defaultLayout $ do
      setTitle $ toHtml appSiteName
      $(widgetFile "homepage")
    provideJson $ object [ "stats" .= object [ "posts"   .= statsAllPosts
                                             , "deleted" .= statsAllDeleted
                                             , "month"   .= statsMonth
                                             , "day"     .= statsDay
                                             , "files"   .= statsAllFiles  
                                             ]
                         , "recent_images" .= recentImages
                         , "news"          .= newsAndFiles
                         , "title"         .= appSiteName  
                         ]
