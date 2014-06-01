{-# LANGUAGE OverloadedStrings #-}
module Handler.EventSource where

import           Import
import           Yesod.Auth

import           Yesod.EventSource
import           Network.Wai.EventSource            (ServerEvent (..))
import           Blaze.ByteString.Builder.Char.Utf8 (fromText)

import qualified Text.Blaze.Html.Renderer.Text   as RHT

import           Data.Aeson
import           Data.Ord               (comparing)
import qualified Data.ByteString.Base64 as Base64
import           Data.Text.Encoding      (encodeUtf8, decodeUtf8)
import qualified Data.Text.Lazy.Encoding as L (decodeUtf8)
import           Data.Text.Lazy          (toStrict)

import           Data.Conduit (yield, bracketP)
import           Control.Concurrent (threadDelay)
import           Control.Monad (forever)
import           Control.Concurrent.STM.TChan
import           Control.Concurrent.STM.TVar
import           Control.Concurrent.STM (atomically)

import qualified Data.Map as Map
import           Data.List (sortBy)
-------------------------------------------------------------------------------------------------------------------
maxConnections :: Int
maxConnections = 500

deleteClient :: Text -> Handler ()
deleteClient posterId = (\clientsRef -> liftIO $ atomically $ modifyTVar' clientsRef (Map.delete posterId)) =<< sseClients <$> getYesod

getPingR :: Handler TypedContent
getPingR = do
  posterId   <- getPosterId
  clientsRef <- sseClients    <$> getYesod
  onlineRef  <- onlineCounter <$> getYesod
  repEventSource $ \_ -> bracketP
    (liftIO $ atomically $ modifyTVar' onlineRef (+1))
    (const $ liftIO $ do
        atomically $ modifyTVar' onlineRef (\x -> x -1)
        atomically $ modifyTVar' clientsRef (Map.delete posterId))
    $ \_ -> forever $ do
        online <- liftIO $ atomically $ readTVar onlineRef
        yield $ ServerEvent Nothing Nothing [fromText $ toStrict $ L.decodeUtf8 $ encode $ toJSON $ object ["online" .= online]]
        liftIO $ threadDelay 500000 -- 0.5 second

getEventR :: SSEListener -> Handler TypedContent
getEventR listener = do
  posterId   <- getPosterId
  clientsRef <- sseClients <$> getYesod
  chan       <- sseChan    <$> getYesod
  clients    <- liftIO $ readTVarIO clientsRef
  let client = Map.lookup posterId clients
  -- delete excess clients if the connection pool is overfilled
  when (Map.size clients > maxConnections) $
    liftIO $ atomically $ modifyTVar' clientsRef (Map.fromList . take (maxConnections-1) .
                                                  sortBy (comparing $ sseClientConnected . snd) . Map.toList)
  -- add a new client to the connection pool
  when (isNothing client) $ do
    muser       <- maybeAuth
    permissions <- getPermissions <$> getMaybeGroup muser
    rating      <- getCensorshipRating
    timeZone    <- getTimeZone
    now         <- liftIO getCurrentTime
    ignoredBoards <- getRecentBoards
    let newClient = SSEClient { sseClientUser        = muser
                              , sseClientPermissions = permissions
                              , sseClientRating      = rating
                              , sseClientTimeZone    = timeZone
                              , sseClientConnected   = now
                              , sseClientRecentIgnoredBoards = ignoredBoards
                              , sseClientListener   = listener
                              }
    liftIO $ atomically $ modifyTVar' clientsRef (Map.insert posterId newClient)
  chan' <- liftIO $ atomically $ dupTChan chan
  repEventSource $ \pf -> do
    yield $ ServerEvent Nothing Nothing [fromText $ "Eventsource works. Used polyfill: " <> showText pf]
    forever $ do
      (name, content) <- liftIO $ atomically $ readTChan chan'
      yield $ ServerEvent (Just $ fromText $ name) Nothing [fromText $ content]
      yield $ ServerEvent Nothing Nothing [fromText $ name <> " : " <> content]

sendPost :: Board -> Int -> Entity Post -> [Entity Attachedfile] -> Bool -> Text -> Handler ()
sendPost boardVal thread ePost files hellbanned posterId = do
  let board           = boardName boardVal
      showPostDate    = boardShowPostDate boardVal
      showEditHistory = boardShowEditHistory boardVal
      geoIpEnabled = boardEnableGeoIp boardVal
  displaySage      <- getConfig configDisplaySage
  maxLenOfFileName <- extraMaxLenOfFileName <$> getExtra

  clientsRef <- sseClients <$> getYesod
  chan       <- sseChan    <$> getYesod
  clients    <- liftIO $ readTVarIO clientsRef
  let access             = boardViewAccess boardVal
      checkViewAccess' u = (isJust access && isNothing ((userGroup . entityVal) <$> u)) ||
                           (isJust access && notElem (fromJust ((userGroup . entityVal) <$> u)) (fromJust access))
      filteredClients = [(k,x) | (k,x) <- Map.toList clients, not hellbanned || k==posterId || elem HellBanP (sseClientPermissions x)
                                                           , not (checkViewAccess' $ sseClientUser x)]
      checkListener client = case sseClientListener client of
        RecentL     -> False
        BoardL  b   -> board == b
        ThreadL b t -> board == b && thread == t

  forM_ filteredClients $ \(posterId', client) -> do
    when (thread /= 0 && checkListener client) $ do
      renderedPost  <- renderPost client ePost displaySage geoIpEnabled maxLenOfFileName showPostDate showEditHistory
      let name        = board <> "-" <> showText thread <> "-" <> posterId'
          encodedPost = decodeUtf8 $ Base64.encode $ encodeUtf8 $ toStrict $ RHT.renderHtml renderedPost
      liftIO $ atomically $ writeTChan chan (name, encodedPost)

    when ( (board `notElem` sseClientRecentIgnoredBoards client) && (sseClientListener client == RecentL) ) $ do
      renderedPost' <- renderPostRecent client ePost geoIpEnabled maxLenOfFileName showPostDate showEditHistory
      let nameRecent     = "recent-" <> posterId'
          encodedPost' = decodeUtf8 $ Base64.encode $ encodeUtf8 $ toStrict $ RHT.renderHtml renderedPost'
      liftIO $ atomically $ writeTChan chan (nameRecent, encodedPost')
  where renderPost client post displaySage geoIpEnabled maxLenOfFileName showPostDate showEditHistory =
          bareLayout $ postWidget post
                       files (sseClientRating client) displaySage True True False
                       geoIpEnabled (sseClientPermissions client)
                       (sseClientTimeZone client) maxLenOfFileName showPostDate showEditHistory
        renderPostRecent client post geoIpEnabled maxLenOfFileName showPostDate showEditHistory =
          bareLayout $ postWidget  post
                       files (sseClientRating client) False True True True
                       geoIpEnabled (sseClientPermissions client)
                       (sseClientTimeZone client) maxLenOfFileName showPostDate showEditHistory

sendDeletedPosts :: [Post] -> Handler ()
sendDeletedPosts posts = do
  clientsRef <- sseClients <$> getYesod
  chan       <- sseChan    <$> getYesod
  clients    <- liftIO $ readTVarIO clientsRef
  let boards  = map postBoard  posts
      threads = map postParent posts
      posts'  = map (\(b,t) -> (b,t,filter (\p -> postBoard p == b && postParent p == t) posts)) $ zip boards threads
  forM_ (Map.keys clients) (\posterId -> forM_ posts' (\(b,t,ps) -> do
      let name     = b <> "-" <> showText t <> "-deleted-" <> posterId
          nameRecent = "recent-deleted-" <> posterId
          postIDs  = map (\x -> "post-" <> showText (postLocalId x) <> "-" <> showText t <> "-" <> b) ps
      liftIO $ atomically $ writeTChan chan (name    , showText postIDs)
      liftIO $ atomically $ writeTChan chan (nameRecent, showText postIDs)
      ))

sendEditedPost :: Text -> Text -> Int -> Int -> Maybe UTCTime -> Handler ()
sendEditedPost msg board thread post time = do
  clientsRef <- sseClients <$> getYesod
  chan       <- sseChan    <$> getYesod
  clients    <- liftIO $ readTVarIO clientsRef
  let filterClients c = flip filter (Map.toList c) $ \(_,v) -> case sseClientListener v of
        RecentL     -> True
        BoardL  b   -> board == b
        ThreadL b t -> board == b && thread == t
  forM_  (filterClients clients) $ \(posterId,client) -> do
      let thread'         = if thread == 0 then post else thread
          name            = board <> "-" <> showText thread' <> "-edited-" <> posterId
          nameRecent        = "recent-edited-" <> posterId
          encodedMsg      = decodeUtf8 $ Base64.encode $ encodeUtf8 msg
          timeZone        = sseClientTimeZone client
          lastModified    = maybe "" (pack . myFormatTime timeZone) time
      liftIO $ atomically $ writeTChan chan (name    , showText [board, showText thread, showText post, encodedMsg, lastModified])
      liftIO $ atomically $ writeTChan chan (nameRecent, showText [board, showText thread, showText post, encodedMsg, lastModified])
