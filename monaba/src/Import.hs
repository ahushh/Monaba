{-# LANGUAGE FlexibleInstances #-}
module Import
    ( module Import
    ) where

import Foundation            as Import
import Import.NoFoundation   as Import
import Import.Utils          as Import
import Import.File           as Import

import Control.Arrow        as Import (first, second, (&&&), (***))
import Database.Persist.Sql as Import (toSqlKey, fromSqlKey)

import           Control.Applicative     (liftA2, (<|>))
import           Data.String
import           Data.Char               (toLower, isPrint)
import           Data.Digest.OpenSSL.MD5 (md5sum)
import           Data.Geolocation.GeoIP
import           Data.Text.Encoding      (decodeUtf8, encodeUtf8)
import           Data.Time               (addUTCTime, secondsToDiffTime)
import           Data.Time.Format        (formatTime)
import           Network.Wai
import           System.FilePath         ((</>))
import           Data.Time.Format        (defaultTimeLocale)
import           System.Random           (randomIO, randomRIO)
import           Text.HTML.TagSoup       (parseTagsOptions, parseOptionsFast, Tag(TagText))
import qualified Data.ByteString.UTF8    as B
import qualified Data.Map.Strict         as MapS
import qualified Data.Text               as T (concat, toLower, append, take)
-------------------------------------------------------------------------------------------------------------------
-- | If ajax request, redirects to page that makes JSON from message and status string.
--   If regular request, redirects to given URL.
trickyRedirect :: (MonadHandler m,
                   RenderMessage (HandlerSite m) msg, RedirectUrl (HandlerSite m) url,
                   RedirectUrl (HandlerSite m) (Route App)) =>
                  Text -> Either msg Text -> url -> m b
trickyRedirect status msg url = do
  let th t = preEscapedToHtml t
      th :: Text -> Html
  either setMessageI (setMessage . th) msg
  t <- isAjaxRequest
  if t
    then redirect (JsonFromMsgR status)
    else redirect url

-------------------------------------------------------------------------------------------------------------------
showWordfilterAction :: WordfilterAction -> AppMessage
showWordfilterAction a = let m' = lookup a xs
                     in case m' of
                       Just m  -> m
                       Nothing -> error "case-of failed at showWordfilterAction"
  where xs = [(WordfilterBan   , MsgWordfilterBan    )
             ,(WordfilterHB    , MsgWordfilterHB     )
             ,(WordfilterHBHide, MsgWordfilterHBHide )
             ,(WordfilterDeny  , MsgWordfilterDeny   )
             ,(WordfilterReplace, MsgWordfilterReplace )
             ]

showWordfilterType :: WordfilterDataType -> AppMessage
showWordfilterType t = let m' = lookup t xs
                     in case m' of
                       Just m  -> m
                       Nothing -> error "case-of failed at showWordfilterType"
  where xs = [(WordfilterWords     , MsgWordfilterWords)
             ,(WordfilterExactMatch, MsgWordfilterExactMatch)
             ,(WordfilterRegex     , MsgWordfilterRegex)
             ]

showPermission :: Permission -> AppMessage
showPermission p = let m' = lookup p xs
                     in case m' of
                       Just m  -> m
                       Nothing -> error "case-of failed at showPermission"
  where xs = [(ManageThreadP    , MsgManageThread    )
             ,(ManageBoardP     , MsgManageBoard     )
             ,(ManageUsersP     , MsgManageUsers     )
             ,(ManageConfigP    , MsgManageConfig    )
             ,(DeletePostsP     , MsgDeletePosts     )
             ,(ManagePanelP     , MsgManagePanel     )
             ,(ManageBanP       , MsgManageBan       )
             ,(EditPostsP       , MsgEditPosts       )
             ,(ShadowEditP      , MsgShadowEdit      ) 
             ,(AdditionalMarkupP, MsgAdditionalMarkup)
             ,(ViewModlogP      , MsgViewModlog      )
             ,(ViewIPAndIDP     , MsgViewIPAndID     )
             ,(HellBanP         , MsgHellbanning     )
             ,(ChangeFileRatingP, MsgChangeFileRating)
             ,(AppControlP      , MsgAppControl)
             ,(WordfilterP      , MsgWordfilter)
             ,(ReportsP         , MsgReports)
             ]

data GroupConfigurationForm = GroupConfigurationForm
                              Text -- ^ Group name
                              Bool -- ^ Permission to manage threads
                              Bool -- ^ ... boards
                              Bool -- ^ ... users
                              Bool -- ^ ... config
                              Bool -- ^ to delete posts
                              Bool -- ^ to view admin panel
                              Bool -- ^ to manage bans
                              Bool -- ^ to edit any post
                              Bool -- ^ Permission to edit any post without saving history  
                              Bool -- ^ to use additional markup
                              Bool -- ^ to view moderation log 
                              Bool -- ^ to view ip and uid
                              Bool -- ^ to use hellbanning 
                              Bool -- ^ to change censorship rating
                              Bool -- ^ to control application
                              Bool -- ^ to configure wordfilter
                              Bool -- ^ to use reports

data BoardConfigurationForm = BoardConfigurationForm
                              (Maybe Text)   -- ^ Name
                              (Maybe Text)   -- ^ Board title
                              (Maybe Int)    -- ^ Bump limit
                              (Maybe Int)    -- ^ Number of files
                              (Maybe Text)   -- ^ Allowed file types
                              (Maybe Text)   -- ^ Default name
                              (Maybe Int )   -- ^ The maximum message length
                              (Maybe Int )   -- ^ Thumbnail size
                              (Maybe Int )   -- ^ Threads per page
                              (Maybe Int )   -- ^ Previews post per thread
                              (Maybe Int )   -- ^ Thread limit
                              (Maybe Text)   -- ^ OP file
                              (Maybe Text)   -- ^ Reply file
                              (Maybe Text)   -- ^ Is hidden (Enable,Disable,DoNotChange)
                              (Maybe Text)   -- ^ Enable captcha (Enable,Disable,DoNotChange)
                              (Maybe Text)   -- ^ Category
                              (Maybe [Text]) -- ^ View access
                              (Maybe [Text]) -- ^ Reply access
                              (Maybe [Text]) -- ^ Thread access
                              (Maybe Text  ) -- ^ Allow OP moderate his/her thread
                              (Maybe Textarea) -- ^ Extra rules
                              (Maybe Text  ) -- ^ Enable geo IP
                              (Maybe Text  ) -- ^ Enable OP editing
                              (Maybe Text  ) -- ^ Enable post editing
                              (Maybe Text  ) -- ^ Show or not editing history
                              (Maybe Text  ) -- ^ Show or not post date
                              (Maybe Text  ) -- ^ Summary
                              (Maybe Text  ) -- ^ Enable forced anonymity (no name input)
                              (Maybe Text  ) -- ^ Required thread title
                              (Maybe Int   ) -- ^ Index
                              (Maybe Text  ) -- ^ Enable private messages
                              (Maybe Text  ) -- ^ Onion access only
-------------------------------------------------------------------------------------------------------------------
-- Search
-------------------------------------------------------------------------------------------------------------------
data SearchResult = SearchResult
    { searchResultPostId  :: PostId
    , searchResultPost    :: Post
    , searchResultExcerpt :: Html
    }

searchForm :: Maybe Text -> Html -> MForm Handler (FormResult (Text, Maybe Text), Widget)
searchForm board = renderDivs $ (,)
                     <$> areq (searchField False) "" Nothing
                     <*> aopt hiddenField "" (Just board)
-------------------------------------------------------------------------------------------------------------------
-- Handful functions
-------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------
-- Files
-------------------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------------------
-- Handler helpers
-------------------------------------------------------------------------------------------------------------------
incPostCount :: Handler ()
incPostCount = do
  pc <- lookupSession "post-count"
  case pc of
    Just n -> setSession "post-count" $ tshow $ plus 1 $ tread n
    Nothing -> setSession "post-count" "1"
    where plus :: Integer -> Integer -> Integer
          plus = (+)

listPages :: Int -> Int -> [Int]
listPages elemsPerPage numberOfElems =
  [0..pagesFix $ floor $ (fromIntegral numberOfElems :: Double) / (fromIntegral elemsPerPage :: Double)]
  where pagesFix x
          | numberOfElems > 0 && numberOfElems `mod` elemsPerPage == 0 = x - 1
          | otherwise                                                = x

getIgnoredBoard :: Maybe Text -> Entity Board -> Maybe Text
getIgnoredBoard group board@(Entity _ b) = if isBoardHidden group board then Just $ boardName b else Nothing

getIgnoredBoard' :: Maybe Text -> Entity Board -> Maybe Text
getIgnoredBoard' group board@(Entity _ b) = if isBoardHidden' group board then Just $ boardName b else Nothing

isBoardHidden :: Maybe Text -> Entity Board -> Bool
isBoardHidden  group x@(Entity _ b) = boardHidden b || isBoardHidden' group x

isBoardHidden' :: Maybe Text -> Entity Board -> Bool
isBoardHidden' group   (Entity _ b) =  (isJust (boardViewAccess b) && isNothing group) || (isJust (boardViewAccess b) && notElem (fromJust group) (fromJust $ boardViewAccess b))


-- | Remove all HTML tags
stripTags :: Text -> Text
stripTags = foldr (T.append . textOnly) "" . parseTagsOptions parseOptionsFast
  where textOnly (TagText t) = t
        textOnly           _ = ""

-- | Check if request has X-Requested-With header
isAjaxRequest :: forall (m :: * -> *). MonadHandler m => m Bool
isAjaxRequest = do
  maybeHeader <- lookup "X-Requested-With" . requestHeaders <$> waiRequest
  return $ maybe False (=="XMLHttpRequest") maybeHeader
-------------------------------------------------------------------------------------------------------------------
-- Template helpers
-------------------------------------------------------------------------------------------------------------------
inc :: Int -> Int
inc = (+1)

makeFileInfo :: Attachedfile -> String
makeFileInfo file = extractFileExt (attachedfileName file) ++", "++ attachedfileSize file ++i
  where i = if length (attachedfileInfo file) > 0 then ", "++ attachedfileInfo file else ""

checkAbbr :: Int  -> -- ^ Message length
            Bool -> -- ^ Show full message
            Bool
checkAbbr len t = len > postAbbrLength && not t

-- | The maximum length of an abbreviated message
postAbbrLength :: Int
postAbbrLength = 1500

enumerate :: forall b. [b] -> [(Int, b)]
enumerate = zip [0..]

ifelse :: Bool -> Text -> Text -> Text
ifelse x y z = if x then y else z

ifelseall :: forall a. Bool -> a -> a -> a
ifelseall x y z = if x then y else z

myFormatTime :: Int     -> -- ^ Time offset in seconds
               UTCTime -> -- ^ UTCTime
               String
myFormatTime offset t = formatTime defaultTimeLocale "%d %B %Y (%a) %H:%M:%S" $ addUTCTime' offset t

-- | Truncate file name if it's length greater than specified
truncateFileName :: Int -> String -> String
truncateFileName maxLen s = if len > maxLen then result else s
  where len      = length s
        excess   = len - maxLen
        halfLen  = round $ fromIntegral len    / (2 :: Double)
        halfExc  = round $ fromIntegral excess / (2 :: Double)
        splitted = splitAt halfLen s
        left     = reverse $ drop (halfExc + 2) $ reverse $ fst splitted
        right    = drop (halfExc + 2) $ snd splitted
        result   = left ++ "[..]" ++ right

defaultTitleMsg title = do
  AppSettings{..} <- appSettings <$> getYesod
  msgrender       <- getMessageRender
  setTitle $ toHtml $ T.concat [appSiteName, appTitleDelimiter, msgrender title]

defaultTitle title = do
  AppSettings{..} <- appSettings <$> getYesod
  setTitle $ toHtml $ T.concat [appSiteName, appTitleDelimiter, title]

defaultTitleReverse title = do
  AppSettings{..} <- appSettings <$> getYesod
  setTitle $ toHtml $ T.concat $ reverse [appSiteName, appTitleDelimiter, title]
-------------------------------------------------------------------------------------------------------------------
-- Widgets
-------------------------------------------------------------------------------------------------------------------
catalogPostWidget :: Entity Post -> [Entity Attachedfile] -> Int -> Widget
catalogPostWidget ePost files replies = do
  let post      = entityVal ePost
      mFile     = if length files > 0 then Just (head files) else Nothing
      msgLength = 35
  rating <- handlerToWidget getCensorshipRating
  AppSettings{..} <- handlerToWidget $ appSettings <$> getYesod
  $(widgetFile "catalog-post")

postWidget :: Entity Post              -> 
             [Entity Attachedfile]    -> 
             Bool                     -> -- ^ Are we in a thread
             Bool                     -> -- ^ Have access to post
             Bool                     -> -- ^ Show parent board/thread in the upper right corner
             Bool                     -> -- ^ If geo ip enabled
             Bool                     -> -- ^ Show post date
             [Permission]             -> -- ^ List of the all permissions
             Int                      -> -- ^ Index number
             Bool                     -> -- ^ Enable PM
             Widget
postWidget ePost eFiles inThread canPost showParent geoIp showPostDate permissions number enablePM = 
  let postVal        = entityVal ePost
      sPostLocalId   = show $ postLocalId $ entityVal ePost
      postLocalId'   = postLocalId $ entityVal ePost
      sPostId        = show $ fromSqlKey  $ entityKey ePost
      postId         = fromSqlKey  $ entityKey ePost
      sThreadLocalId = show $ postParent  $ entityVal ePost
      threadLocalId  = postParent  $ entityVal ePost
      board          = postBoard $ entityVal ePost
      isThread       = sThreadLocalId == "0"
      pClass'        = (if isThread then "op" else "reply") <> (if elem HellBanP permissions && postHellbanned postVal then " hellbanned" else "")  :: Text
      itsforMe uid   = maybe True (==uid) (postDestUID $ entityVal ePost) || uid == (postPosterId $ entityVal ePost)
      destUID        = postDestUID $ entityVal ePost
  in do
    timeZone        <- handlerToWidget getTimeZone
    rating          <- handlerToWidget getCensorshipRating
    posterId        <- handlerToWidget getPosterId
    AppSettings{..} <- handlerToWidget $ appSettings <$> getYesod
    inBookmarks     <- handlerToWidget $ do
      bm <- getBookmarks
      return $ isJust $ lookup (fromIntegral postId) bm

    req <- handlerToWidget $ waiRequest
    app <- handlerToWidget $ getYesod
    let pClass   = pClass' <> if posterId == postPosterId postVal then " my" else ""
    let approot' =  case appRoot of
                      Nothing -> getApprootText guessApproot app req
                      Just root -> root
    $(widgetFile "post")

paginationWidget page pages route = $(widgetFile "pagination")

deleteWidget :: [Permission] -> Widget
deleteWidget permissions = $(widgetFile "delete")

adminNavbarWidget :: Widget
adminNavbarWidget = do
  permissions <- handlerToWidget $ ((fmap getPermissions) . getMaybeGroup) =<< maybeAuth
  reports <- handlerToWidget $ runDB $ count ([]::[Filter Report])
  $(widgetFile "admin/navbar")
-------------------------------------------------------------------------------------------------------------------
bareLayout :: Yesod site => WidgetT site IO () -> HandlerT site IO Html
bareLayout widget = do
    pc <- widgetToPageContent widget
    withUrlRenderer [hamlet| ^{pageBody pc} |]
-------------------------------------------------------------------------------------------------------------------
-- Access checkers
-------------------------------------------------------------------------------------------------------------------
checkHellbanned :: Post -> [Permission] -> Text -> Bool
checkHellbanned post permissions posterId = not (postHellbanned post) ||
                                            elem HellBanP permissions ||
                                            (postPosterId post) == posterId
checkAccessToReply :: Maybe (Entity Group) -> Board -> Bool
checkAccessToReply mgroup boardVal =
  let group  = (groupName . entityVal) <$> mgroup
      access = boardReplyAccess boardVal
  in isNothing access || (isJust group && elem (fromJust group) (fromJust access))

checkAccessToNewThread :: Maybe (Entity Group) -> Board -> Bool
checkAccessToNewThread mgroup boardVal =
  let group  = (groupName . entityVal) <$> mgroup
      access = boardThreadAccess boardVal
  in isNothing access || (isJust group && elem (fromJust group) (fromJust access))

checkViewAccess' :: forall (m :: * -> *). MonadHandler m => Maybe (Entity Group) -> Board -> m Bool
checkViewAccess' mgroup boardVal = do
  let group  = (groupName . entityVal) <$> mgroup
      access = boardViewAccess boardVal
  ip <- pack <$> getIp
  return $ not ( (isJust access && isNothing group) ||
               (isJust access && notElem (fromJust group) (fromJust access)) ||
               (boardOnion boardVal && not (isOnion ip))
             )

checkViewAccess :: forall (m :: * -> *). MonadHandler m => Maybe (Entity Group) -> Board -> m () 
checkViewAccess mgroup boardVal = do
  let group  = (groupName . entityVal) <$> mgroup
      access = boardViewAccess boardVal
  ip <- pack <$> getIp
  when ( (isJust access && isNothing group) ||
         (isJust access && notElem (fromJust group) (fromJust access)) ||
         (boardOnion boardVal && not (isOnion ip))
       ) notFound

isOnion :: forall a. (Eq a, Data.String.IsString a) => a -> Bool
isOnion = (=="172.19.0.4")

getPermissions :: Maybe (Entity Group) -> [Permission]
getPermissions = maybe [] (groupPermissions . entityVal)
-------------------------------------------------------------------------------------------------------------------
-- Some getters
-------------------------------------------------------------------------------------------------------------------
getMaybeGroup :: Maybe (Entity User) -> Handler (Maybe (Entity Group))
getMaybeGroup muser = case muser of
    Just (Entity _ u) -> runDB $ getBy $ GroupUniqName $ userGroup u
    _                 -> return Nothing
    
getBoardVal404 :: Text -> Handler Board
getBoardVal404 board = runDB (getBy $ BoardUniqName board) >>= maybe notFound (return . entityVal)

getTimeZone :: Handler Int
getTimeZone = do
  defaultZone <- appTimezone . appSettings <$> getYesod
  timezone    <- lookupSession "timezone"
  return $ maybe defaultZone tread timezone

getCensorshipRating :: Handler Censorship
getCensorshipRating = do
  mRating <- lookupSession "censorship-rating"
  case mRating of
    Just rating -> return $ tread rating
    Nothing     -> setSession "censorship-rating" "SFW" >> return SFW

getPosterId :: Handler Text
getPosterId = do
  maybePosterId <- lookupSession "posterId"
  case maybePosterId of
    Just posterId -> return posterId
    Nothing       -> do
      posterId <- liftIO $ pack . md5sum . B.fromString <$> liftA2 (++) (show <$> (randomIO :: IO Int)) (show <$> getCurrentTime)
      setSession "posterId" posterId
      return posterId

getConfig :: forall b. (Config -> b) -> Handler b
getConfig f = f . entityVal . fromJust <$> runDB (selectFirst ([]::[Filter Config]) [])

getConfigEntity :: Handler Config
getConfigEntity = entityVal . fromJust <$> runDB (selectFirst ([]::[Filter Config]) [])

getFeedBoards :: Handler [Text]
getFeedBoards = do
  bs <- lookupSession "feed-ignore-boards"
  case bs of
   Just xs -> return $ tread xs
   Nothing -> setSession "feed-ignore-boards" "[]" >> return []

getHiddenThreads :: Text -> Handler [(Int,Int)]
getHiddenThreads board = do
  ht <- lookupSession "hidden-threads"
  case ht of
   Just xs -> return $ fromMaybe [] $ lookup board (read (unpack xs) :: [(Text, [(Int,Int)])])
   Nothing -> setSession "hidden-threads" "[]" >> return []

getAllHiddenThreads :: Handler [(Text, [(Int,Int)])]
getAllHiddenThreads = do
  ht <- lookupSession "hidden-threads"
  case ht of
   Just xs -> return $ read $ unpack xs
   Nothing -> setSession "hidden-threads" "[]" >> return []

getBookmarks :: Handler [(Int, Int)]
getBookmarks = do
  bm <- lookupSession "bookmarks"
  case bm of
   Just xs -> return $ read $ unpack xs
   Nothing -> setSession "bookmarks" "[]" >> return []


getAllHiddenPostsIds :: [Text] -> Handler [Key Post]
getAllHiddenPostsIds boards = do
  threadsIds <- concat <$> forM boards (\b -> map (toSqlKey . fromIntegral . snd) <$> getHiddenThreads b)
  threads    <- runDB $ selectList [PostId <-. threadsIds] []
  replies    <- runDB $ forM threads $ \(Entity _ t) -> selectList [PostBoard ==. postBoard t, PostParent ==. postLocalId t] []
  return $ map f threads ++ map f (concat replies)
  where f (Entity k _) = k
-------------------------------------------------------------------------------------------------------------------
-- IP getter
-------------------------------------------------------------------------------------------------------------------
-- | Gets IP from X-Real-IP/CF-Connecting-I or remote-host header
getIp = do
  realIp <- fmap B.toString <$> getIpReal
  cfIp   <- fmap B.toString <$> getIpCF
  hostIp <- getIpFromHost
  let resultIp = fromJust (cfIp <|> realIp <|> Just hostIp)
  return resultIp
  where getIpReal      = lookup "X-Real-IP" . requestHeaders <$> waiRequest
        getIpCF        = lookup "CF-Connecting-IP" . requestHeaders <$> waiRequest
        getIpFromHost  = takeWhile (not . (`elem` (":"::String))) . show . remoteHost . reqWaiRequest <$> getRequest
-------------------------------------------------------------------------------------------------------------------
-- Geo IP
-------------------------------------------------------------------------------------------------------------------  
getCountry :: Text ->                      -- ^ IP adress
             Handler (Maybe (Text,Text)) -- ^ (country code, country name)
getCountry ip = do
  dbPath   <- unpack . appGeoIPCityPath . appSettings <$> getYesod
  geoIpRes <- liftIO $ openGeoDB memory_cache dbPath >>= flip geoLocateByIPAddress (encodeUtf8 ip)
  return $ ((decodeUtf8 . geoCountryCode) &&& (decodeUtf8 . geoCountryName)) <$> geoIpRes
-------------------------------------------------------------------------------------------------------------------
-- Board stats
-------------------------------------------------------------------------------------------------------------------
getBoardStats :: Handler [(Text,Int,Int)]
getBoardStats = do
  mgroup     <- (fmap $ userGroup . entityVal) <$> maybeAuth
  maybeStats <- lookupSession "board-stats"
  case maybeStats of
    Just s  -> return $ tread s
    Nothing -> do
      posterId <- getPosterId
      boards <- map (boardName . entityVal) . filter (not . isBoardHidden mgroup) <$> runDB (selectList ([]::[Filter Board]) [])
      hiddenThreads <- getAllHiddenThreads
      stats  <- runDB $ forM boards $ \b -> do
                  lastPost <- selectFirst [PostBoard ==. b, PostDeleted ==. False, PostPosterId !=. posterId, PostHellbanned ==. False
                                         ,PostParent /<-. concatMap (map fst . snd) (filter ((==b).fst) hiddenThreads)] [Desc PostLocalId]
                  return (b, maybe 0 (postLocalId . entityVal) lastPost, 0)
      saveBoardStats stats
      return stats

saveBoardStats :: [(Text,Int,Int)] -> Handler ()
saveBoardStats stats = do
  deleteSession "board-stats"
  setSession "board-stats" $ tshow stats

cleanAllBoardsStats :: Handler ()
cleanAllBoardsStats = do
  mgroup <- (fmap $ userGroup . entityVal) <$> maybeAuth
  boards <- map (boardName . entityVal) . filter (not . isBoardHidden mgroup) <$> runDB (selectList ([]::[Filter Board]) [])
  forM_ boards cleanBoardStats
  
cleanBoardStats :: Text -> Handler ()
cleanBoardStats board = do
  hiddenThreads <- getAllHiddenThreads
  oldStats <- getBoardStats
  newStats <- forM oldStats $ \s@(b,_,_) ->
    if b == board
    then do
      lastPost <- runDB $ selectFirst [PostBoard ==. b, PostDeleted ==. False, PostHellbanned ==. False
                                      ,PostParent /<-. concatMap (map fst . snd) (filter ((==b).fst) hiddenThreads)] [Desc PostLocalId]
      return (b, maybe 0 (postLocalId . entityVal) lastPost, 0)
    else return s
  saveBoardStats newStats


-------------------------------------------------------------------------------------------------------------------
-- JSON instances
-------------------------------------------------------------------------------------------------------------------
data PostAndFiles = PostAndFiles (Entity Post, [Entity Attachedfile])
type OpPostAndFiles = PostAndFiles
data ThreadsAndPreviews = ThreadsAndPreviews [( OpPostAndFiles
                                              , [PostAndFiles]
                                              , Int
                                              )]

appUploadDir' :: String
appUploadDir' = "upload"

appStaticDir' :: String
appStaticDir' = "static"

instance ToJSON Attachedfile where
    toJSON Attachedfile {..} = object
        [ "hashsum"         .= attachedfileHashsum
        , "name"        .= attachedfileName
        , "extension"   .= attachedfileExtension
        , "thumbSize"   .= attachedfileThumbSize
        , "thumbWidth"  .= attachedfileThumbWidth
        , "thumbHeight" .= attachedfileThumbHeight
        , "size"        .= attachedfileSize
        , "info"        .= attachedfileInfo
        , "path"        .= attachedfilePath
        , "rating"      .= attachedfileRating  
        , "thumb_path"  .= thumbUrlPath appUploadDir' appStaticDir' attachedfileThumbSize attachedfileFiletype attachedfileExtension attachedfileHashsum attachedfileOnion 
        ]

instance ToJSON Post where
    toJSON Post {..} = object
        [ "board"       .= postBoard
        , "id"          .= postLocalId
        , "parent"      .= postParent
        , "date"        .= postDate
        , "bumped"      .= postBumped
        , "sticked"     .= postSticked
        , "locked"      .= postLocked
        , "autosage"    .= postAutosage
        , "message"     .= postMessage
        , "rawMessage"  .= postRawMessage
        , "title"       .= postTitle
        , "name"        .= postName
        , "deletedByOp" .= postDeletedByOp
        ]
    

instance ToJSON (Entity Attachedfile) where
    toJSON (Entity k v) = toJSON v

instance ToJSON (Entity Post) where
    toJSON (Entity k v) = toJSON v

instance ToJSON PostAndFiles where
  toJSON (PostAndFiles (post, files)) = object [ "post"  .= post,
                                                 "files" .= files
                                               ]

instance ToJSON ThreadsAndPreviews where
  toJSON (ThreadsAndPreviews threads) = array $ map
                                        (\(op, replies, omitted) -> object [ "op"      .= op
                                                                           , "replies" .= replies
                                                                           , "omitted" .= omitted
                                                                           ])
                                        threads
