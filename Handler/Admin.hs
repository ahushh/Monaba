{-# LANGUAGE TupleSections, OverloadedStrings #-}
module Handler.Admin where

import           Import
import           Yesod.Auth
import qualified Data.Text         as T
import           Yesod.Auth.HashDB (setPassword)
import           Handler.Delete    (deletePosts)
import           Control.Monad     (mplus)
-------------------------------------------------------------------------------------------------------------
getAdminR :: Handler Html
getAdminR = do
  muser     <- maybeAuth
  boards    <- runDB $ selectList ([]::[Filter Board]) []
  boardCategories <- getConfig configBoardCategories
  nameOfTheBoard  <- extraSiteName <$> getExtra
  defaultLayout $ do
    setTitle $ toHtml $ T.concat [nameOfTheBoard, " - ", "Management"]
    $(widgetFile "admin")
-------------------------------------------------------------------------------------------------------------
-- Thread options    
-------------------------------------------------------------------------------------------------------------
getStickR :: Text -> Int -> Handler Html
getStickR board thread = do
  maybePost <- runDB $ selectFirst [PostBoard ==. board, PostLocalId ==. thread] []
  case maybePost of
    Just (Entity pId p) -> runDB (update pId [PostSticked =. not (postSticked p)]) >> redirectUltDest AdminR
    _                   -> setMessageI MsgNoSuchThread >> redirectUltDest AdminR
      
getLockR :: Text -> Int -> Handler Html
getLockR board thread = do
  maybePost <- runDB $ selectFirst [PostBoard ==. board, PostLocalId ==. thread] []
  case maybePost of
    Just (Entity pId p) -> runDB (update pId [PostLocked =. not (postLocked p)]) >> redirectUltDest AdminR
    _                   -> setMessageI MsgNoSuchThread >> redirectUltDest AdminR
      
getAutoSageR :: Text -> Int -> Handler Html
getAutoSageR board thread = do
  maybePost <- runDB $ selectFirst [PostBoard ==. board, PostLocalId ==. thread] []
  case maybePost of
    Just (Entity pId p) -> runDB (update pId [PostAutosage =. not (postAutosage p)]) >> redirectUltDest AdminR
    _                   -> setMessageI MsgNoSuchThread >> redirectUltDest AdminR
    
-------------------------------------------------------------------------------------------------------------
---------------------------------- WHERE IS YESOD'S BUILTIN CRUD ??? ----------------------------------------
-------------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------------
-- Bans    
-------------------------------------------------------------------------------------------------------------
banByIpForm :: Text -> Text -> Html -> MForm Handler (FormResult (Text, Text, Maybe Text, Maybe Int), Widget)
banByIpForm ip board extra = do
  (ipRes     , ipView     ) <- mreq textField  "" (Just ip)
  (reasonRes , reasonView ) <- mreq textField  "" Nothing
  (boardRes  , boardView  ) <- mopt textField  "" (Just $ Just board)
  (expiresRes, expiresView) <- mopt intField   "" Nothing
  let result = (,,,) <$> ipRes <*> reasonRes <*> boardRes <*> expiresRes
      widget = $(widgetFile "admin/ban-form")
  return (result, widget)
                                          
getBanByIpR :: Text -> Text -> Handler Html    
getBanByIpR board ip = do
  (formWidget, formEnctype) <- generateFormPost $ banByIpForm ip board
  muser  <- maybeAuth
  boards <- runDB $ selectList ([]::[Filter Board]) []
  bans   <- runDB $ selectList ([]::[Filter Ban])   []
  nameOfTheBoard <- extraSiteName <$> getExtra
  boardCategories <- getConfig configBoardCategories
  defaultLayout $ do
    setTitle $ toHtml $ T.concat [nameOfTheBoard, " - ", "Ban management"]
    $(widgetFile "admin/ban")
  
postBanByIpR :: Text -> Text -> Handler Html
postBanByIpR _ _ = do
  ((result, _), _) <- runFormPost $ banByIpForm "" ""
  let msgRedirect msg = setMessageI msg >> redirect (BanByIpR "" "")
  case result of
    FormFailure _                            -> msgRedirect MsgBadFormData
    FormMissing                              -> msgRedirect MsgNoFormData
    FormSuccess (ip, reason, board, expires) -> do
      now <- liftIO getCurrentTime
      let newBan = Ban { banIp      = ip
                       , banReason  = reason
                       , banBoard   = board
                       , banExpires = (\n -> addUTCTime' (60*60*n) now) <$> expires
                       }
      void $ runDB $ insert newBan
      msgRedirect MsgBanAdded

getBanDeleteR :: Int -> Handler Html
getBanDeleteR bId = runDB (delete (toKey bId :: Key Ban)) >> setMessageI MsgBanDeleted >> redirect (BanByIpR "" "")
-------------------------------------------------------------------------------------------------------------
-- Boards management
-------------------------------------------------------------------------------------------------------------
getManageBoardsR :: Text -> Handler Html
getManageBoardsR board = do
  maybeBoard <- runDB $ selectFirst [BoardName ==. board] []
  (formWidget, formEnctype) <- generateFormPost $ updateBoardForm maybeBoard board
  muser  <- maybeAuth
  boards <- runDB $ selectList ([]::[Filter Board]) []
  boardCategories <- getConfig configBoardCategories
  nameOfTheBoard <- extraSiteName <$> getExtra
  defaultLayout $ do
    setTitle $ toHtml $ T.concat [nameOfTheBoard, " - ", "Board management"]
    $(widgetFile "admin/boards")
    
updateBoardForm :: Maybe (Entity Board) -> 
                  Text -> -- board name
                  Html -> -- extra
                  MForm Handler (FormResult ( Maybe Text -- name
                                            , Maybe Text -- description
                                            , Maybe Int  -- bump limit
                                            , Maybe Int  -- number of files
                                            , Maybe Text -- allowed file typs
                                            , Maybe Text -- default name
                                            , Maybe Int  -- max msg length
                                            , Maybe Int  -- thumb size
                                            , Maybe Int  -- threads per page
                                            , Maybe Int  -- previews per thread
                                            , Maybe Int  -- thread limit
                                            , Maybe Bool -- is hidden
                                            , Maybe Bool -- enable captcha
                                            , Maybe Text -- category
                                            )
                                , Widget)
updateBoardForm board bname' extra = do
  let f g = maybe Nothing (Just . Just . g . entityVal) board
      f :: (Board -> a) -> Maybe (Maybe a)
  (nameRes             , nameView             ) <- mopt textField     "" (f boardName)
  (descriptionRes      , descriptionView      ) <- mopt textField     "" (f boardDescription)
  (bumpLimitRes        , bumpLimitView        ) <- mopt intField      "" (f boardBumpLimit)
  (numberFilesRes      , numberFilesView      ) <- mopt intField      "" (f boardNumberFiles)
  (allowedTypesRes     , allowedTypesView     ) <- mopt textField     "" (f (pack . unwords . boardAllowedTypes))
  (defaultNameRes      , defaultNameView      ) <- mopt textField     "" (f boardDefaultName)
  (maxMsgLengthRes     , maxMsgLengthView     ) <- mopt intField      "" (f boardMaxMsgLength)
  (thumbSizeRes        , thumbSizeView        ) <- mopt intField      "" (f boardThumbSize)
  (threadsPerPageRes   , threadsPerPageView   ) <- mopt intField      "" (f boardThreadsPerPage)
  (previewsPerThreadRes, previewsPerThreadView) <- mopt intField      "" (f boardPreviewsPerThread)
  (threadLimitRes      , threadLimitView      ) <- mopt intField      "" (maybe Nothing (Just . boardThreadLimit . entityVal) board)
  (isHiddenRes         , isHiddenView         ) <- mopt checkBoxField "" (f boardHidden)
  (categoryRes         , categoryView         ) <- mopt textField     "" (maybe Nothing (Just . boardCategory . entityVal) board)
  (enableCaptchaRes    , enableCaptchaView    ) <- mopt checkBoxField "" (f boardEnableCaptcha)
  let result = (,,,,,,,,,,,,,) <$> nameRes <*> descriptionRes <*>
               bumpLimitRes <*> numberFilesRes <*> allowedTypesRes <*>
               defaultNameRes <*> maxMsgLengthRes <*> thumbSizeRes <*>
               threadsPerPageRes <*> previewsPerThreadRes <*> threadLimitRes <*>
               isHiddenRes <*> enableCaptchaRes <*> categoryRes
      bname  = maybe bname' (boardName . entityVal) board
      widget = $(widgetFile "admin/boards-form")
  return (result, widget)

postManageBoardsR :: Text -> Handler Html
postManageBoardsR board = do
  maybeBoard <- runDB $ selectFirst [BoardName ==. board] []
  ((result, _), _) <- runFormPost $ updateBoardForm maybeBoard board
  let msgRedirect msg = setMessageI msg >> redirect (ManageBoardsR board)
  case result of
    FormFailure _                            -> msgRedirect MsgBadFormData
    FormMissing                              -> msgRedirect MsgNoFormData
    FormSuccess (bName, bDesc, bBumpLimit, bNumberFiles, bAllowedTypes,
                bDefaultName, bMaxMsgLen, bThumbSize, bThreadsPerPage,
                bPrevPerThread, bThreadLimit, bIsHidden,
                bEnableCaptcha, bCategory) ->
      case board of
        "new" -> do
          when (any isNothing [bName, bDesc, bAllowedTypes, bDefaultName] ||
                any isNothing [bBumpLimit, bNumberFiles, bMaxMsgLen, bThumbSize, bThreadsPerPage, bPrevPerThread]) $
            setMessageI MsgUpdateBoardsInvalidInput >> redirect (ManageBoardsR board)            
          let newBoard = Board { boardName              = fromJust bName
                               , boardDescription       = fromJust bDesc
                               , boardBumpLimit         = fromJust bBumpLimit
                               , boardNumberFiles       = fromJust bNumberFiles
                               , boardAllowedTypes      = words    $ unpack $ fromJust bAllowedTypes
                               , boardDefaultName       = fromJust bDefaultName
                               , boardMaxMsgLength      = fromJust bMaxMsgLen
                               , boardThumbSize         = fromJust bThumbSize
                               , boardThreadsPerPage    = fromJust bThreadsPerPage
                               , boardPreviewsPerThread = fromJust bPrevPerThread
                               , boardThreadLimit       = bThreadLimit
                               , boardHidden            = fromJust bIsHidden
                               , boardEnableCaptcha     = fromJust bEnableCaptcha
                               , boardCategory          = bCategory
                               }
          void $ runDB $ insert newBoard
          msgRedirect MsgBoardAdded
        "all" -> do
          boards <- runDB $ selectList ([]::[Filter Board]) []
          forM_ boards $ \(Entity oldBoardId oldBoard) ->
              let newBoard = Board { boardName              = boardName oldBoard
                                   , boardDescription       = fromMaybe (boardDescription       oldBoard) bDesc
                                   , boardBumpLimit         = fromMaybe (boardBumpLimit         oldBoard) bBumpLimit
                                   , boardNumberFiles       = fromMaybe (boardNumberFiles       oldBoard) bNumberFiles
                                   , boardAllowedTypes      = maybe     (boardAllowedTypes      oldBoard) (words . unpack) bAllowedTypes
                                   , boardDefaultName       = fromMaybe (boardDefaultName       oldBoard) bDefaultName
                                   , boardMaxMsgLength      = fromMaybe (boardMaxMsgLength      oldBoard) bMaxMsgLen
                                   , boardThumbSize         = fromMaybe (boardThumbSize         oldBoard) bThumbSize
                                   , boardThreadsPerPage    = fromMaybe (boardThreadsPerPage    oldBoard) bThreadsPerPage
                                   , boardPreviewsPerThread = fromMaybe (boardPreviewsPerThread oldBoard) bPrevPerThread
                                   , boardThreadLimit       = mplus bThreadLimit Nothing
                                   , boardHidden            = fromMaybe (boardHidden            oldBoard) bIsHidden
                                   , boardEnableCaptcha     = fromMaybe (boardEnableCaptcha     oldBoard) bEnableCaptcha
                                   , boardCategory          = mplus bCategory Nothing
                                   }
                in runDB $ replace oldBoardId newBoard
          msgRedirect MsgBoardsUpdated
        _     -> do -- update existing board
          let oldBoard   = entityVal $ fromJust maybeBoard
              oldBoardId = entityKey $ fromJust maybeBoard
              newBoard = Board { boardName              = fromMaybe (boardName oldBoard) bName
                               , boardDescription       = fromMaybe (boardDescription       oldBoard) bDesc
                               , boardBumpLimit         = fromMaybe (boardBumpLimit         oldBoard) bBumpLimit
                               , boardNumberFiles       = fromMaybe (boardNumberFiles       oldBoard) bNumberFiles
                               , boardAllowedTypes      = maybe     (boardAllowedTypes      oldBoard) (words . unpack) bAllowedTypes
                               , boardDefaultName       = fromMaybe (boardDefaultName       oldBoard) bDefaultName
                               , boardMaxMsgLength      = fromMaybe (boardMaxMsgLength      oldBoard) bMaxMsgLen
                               , boardThumbSize         = fromMaybe (boardThumbSize         oldBoard) bThumbSize
                               , boardThreadsPerPage    = fromMaybe (boardThreadsPerPage    oldBoard) bThreadsPerPage
                               , boardPreviewsPerThread = fromMaybe (boardPreviewsPerThread oldBoard) bPrevPerThread
                               , boardThreadLimit       = mplus bThreadLimit Nothing
                               , boardHidden            = fromMaybe (boardHidden            oldBoard) bIsHidden
                               , boardEnableCaptcha     = fromMaybe (boardEnableCaptcha     oldBoard) bEnableCaptcha
                               , boardCategory          = mplus bCategory Nothing
                               }
          runDB $ replace oldBoardId newBoard
          msgRedirect MsgBoardsUpdated

cleanBoard :: Text -> Handler ()
cleanBoard board = case board of
  "all" -> do
    boards  <- runDB $ selectList ([]::[Filter Board ]) []
    postIDs <- forM boards $ \(Entity _ b) -> runDB $ selectList [PostBoard ==. boardName b] []
    void $ deletePosts $ concat postIDs
  "new" -> msgRedirect MsgNoSuchBoard
  _     -> do
    maybeBoard <- runDB $ selectFirst [BoardName ==. board] []  
    when (isNothing maybeBoard) $ msgRedirect MsgNoSuchBoard
    postIDs <- runDB $ selectList [PostBoard ==. board] []
    void $ deletePosts postIDs
  where msgRedirect msg = setMessageI msg >> redirect (ManageBoardsR board)

getCleanBoardR :: Text -> Handler ()
getCleanBoardR board = do
  cleanBoard board
  setMessageI MsgBoardCleaned
  redirect (ManageBoardsR board)

getDeleteBoardR :: Text -> Handler ()
getDeleteBoardR board = do
  cleanBoard board
  case board of
    "all" -> runDB $ deleteWhere ([]::[Filter Board ])
    _     -> runDB $ deleteWhere [BoardName ==. board]
  setMessageI MsgBoardDeleted
  redirect (ManageBoardsR "all")
-------------------------------------------------------------------------------------------------------------
-- Staff  
-------------------------------------------------------------------------------------------------------------
staffForm :: Html -> MForm Handler (FormResult (Text, Text, RoleOfPerson), Widget)
staffForm extra = do
  (personNameRes     , personNameView     ) <- mreq textField               "" Nothing
  (personPasswordRes , personPasswordView ) <- mreq textField               "" Nothing
  (personRoleRes     , personRoleView     ) <- mreq (selectFieldList roles) "" Nothing
  let result = (,,) <$> personNameRes <*> personPasswordRes <*> personRoleRes
      widget = $(widgetFile "admin/staff-form")
  return (result, widget)
    where roles :: [(Text, RoleOfPerson)]
          roles = [("admin",Admin), ("mod",Moderator)]

getStaffR :: Handler Html
getStaffR = do
  muser     <- maybeAuth
  boards    <- runDB $ selectList ([]::[Filter Board ]) []
  persons   <- runDB $ selectList ([]::[Filter Person]) []
  (formWidget, formEnctype) <- generateFormPost staffForm
  nameOfTheBoard <- extraSiteName <$> getExtra
  boardCategories <- getConfig configBoardCategories
  defaultLayout $ do
    setTitle $ toHtml $ T.concat [nameOfTheBoard, " - ", "Staff"]
    $(widgetFile "admin/staff")

postStaffR :: Handler Html
postStaffR = do
  ((result, _), _) <- runFormPost staffForm
  let msgRedirect msg = setMessageI msg >> redirect StaffR
  case result of
    FormFailure _                      -> msgRedirect MsgBadFormData
    FormMissing                        -> msgRedirect MsgNoFormData
    FormSuccess (name, password, role) -> do
      let newPerson = Person { personName     = name
                             , personPassword = ""
                             , personSalt     = ""
                             , personRole     = role
                             }
      personWithPassword <- liftIO $ setPassword password newPerson
      void $ runDB $ insert personWithPassword
      msgRedirect MsgStaffAdded

getStaffDeleteR :: Int -> Handler Html
getStaffDeleteR userId = do
  let msgRedirect msg = setMessageI msg >> redirect StaffR
  whenM ((>1) <$> runDB (count [PersonRole ==. Admin])) $ do
     runDB $ delete (toKey userId :: Key Person)
     msgRedirect MsgStaffDeleted
  msgRedirect MsgYouAreTheOnlyAdmin
-------------------------------------------------------------------------------------------------------------
-- Account  
-------------------------------------------------------------------------------------------------------------
newPasswordForm :: Html -> MForm Handler (FormResult Text, Widget)
newPasswordForm extra = do
  (newPasswordRes , newPasswordView ) <- mreq textField "" Nothing
  let widget = toWidget [whamlet|
                             <form method=post action=@{NewPasswordR}>
                                 #{extra}
                                  <input type=submit value=_{MsgNewPassword}>
                                 ^{fvInput newPasswordView}
                        |]
  return (newPasswordRes, widget)

getAccountR :: Handler Html
getAccountR = do
  muser     <- maybeAuth
  boards    <- runDB $ selectList ([]::[Filter Board ]) []
  (formWidget, formEnctype) <- generateFormPost newPasswordForm
  nameOfTheBoard <- extraSiteName <$> getExtra
  boardCategories <- getConfig configBoardCategories
  defaultLayout $ do
    setTitle $ toHtml $ T.concat [nameOfTheBoard, " - ", "Account"]
    $(widgetFile "admin/account")
                 
postNewPasswordR :: Handler Html
postNewPasswordR = do
  ((result, _), _) <- runFormPost newPasswordForm
  let msgRedirect msg = setMessageI msg >> redirect AccountR
  case result of
    FormFailure _           -> msgRedirect MsgBadFormData
    FormMissing             -> msgRedirect MsgNoFormData
    FormSuccess newPassword -> do
      muser <- maybeAuth
      personWithNewPassword <- liftIO $ setPassword newPassword $ entityVal $ fromJust muser
      void $ runDB $ replace (entityKey $ fromJust muser) personWithNewPassword
      msgRedirect MsgPasswordChanged
      
-------------------------------------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------------------------------------
configForm :: Config -> Html -> MForm Handler (FormResult ( Maybe Int -- captcha length
                                                       , Maybe Int -- adaptive captcha guards
                                                       , Maybe Int -- captcha timeout
                                                       , Maybe Int -- reply delay
                                                       , Maybe Int -- new thread delay
                                                       , Maybe Text -- board categories
                                                       )
                                           , Widget)
configForm config extra = do
  let f g = Just $ Just $ g config
  (captchaLengthRes   , captchaLengthView  ) <- mopt intField  "" (f configCaptchaLength  )
  (acaptchaGuardsRes  , acaptchaGuardsView ) <- mopt intField  "" (f configACaptchaGuards )
  (captchaTimeoutRes  , captchaTimeoutView ) <- mopt intField  "" (f configCaptchaTimeout )
  (replyDelayRes      , replyDelayView     ) <- mopt intField  "" (f configReplyDelay     )
  (threadDelayRes     , threadDelayView    ) <- mopt intField  "" (f configThreadDelay    )
  (boardCategoriesRes , boardCategoriesView) <- mopt textField "" (Just $ Just $ T.intercalate "," $ configBoardCategories config)
  let result = (,,,,,) <$> captchaLengthRes <*> acaptchaGuardsRes <*>
               captchaTimeoutRes <*> replyDelayRes <*> threadDelayRes <*> boardCategoriesRes
      widget = $(widgetFile "admin/config-form")
  return (result, widget)

getConfigR :: Handler Html
getConfigR = do
  muser  <- maybeAuth
  boards <- runDB $ selectList  ([]::[Filter Board ]) []
  config <- runDB $ selectFirst ([]::[Filter Config]) []
  (formWidget, formEnctype) <- generateFormPost $ configForm (entityVal $ fromJust config)
  nameOfTheBoard <- extraSiteName <$> getExtra
  boardCategories <- getConfig configBoardCategories
  defaultLayout $ do
    setTitle $ toHtml $ T.concat [nameOfTheBoard, " - ", "Config"]
    $(widgetFile "admin/config")

postConfigR :: Handler Html
postConfigR = do
  oldConfig        <- fromJust <$> runDB (selectFirst ([]::[Filter Config]) []  )
  ((result, _), _) <- runFormPost $ configForm (entityVal oldConfig)
  let msgRedirect msg = setMessageI msg >> redirect ConfigR
  case result of
    FormFailure _                      -> msgRedirect MsgBadFormData
    FormMissing                        -> msgRedirect MsgNoFormData
    FormSuccess (captchaLength, aCaptchaGuards, captchaTimeout, replyDelay, threadDelay, boardCategories) -> do
      let newConfig = Config { configCaptchaLength   = fromMaybe (configCaptchaLength   $ entityVal oldConfig) captchaLength
                             , configACaptchaGuards  = fromMaybe (configACaptchaGuards  $ entityVal oldConfig) aCaptchaGuards
                             , configCaptchaTimeout  = fromMaybe (configCaptchaTimeout  $ entityVal oldConfig) captchaTimeout
                             , configReplyDelay      = fromMaybe (configReplyDelay      $ entityVal oldConfig) replyDelay
                             , configThreadDelay     = fromMaybe (configThreadDelay     $ entityVal oldConfig) threadDelay
                             , configBoardCategories = maybe     (configBoardCategories $ entityVal oldConfig) (T.splitOn ",") boardCategories
                             }
      void $ runDB $ replace (entityKey oldConfig) newConfig
      msgRedirect MsgConfigUpdated
