{-# LANGUAGE FlexibleInstances #-}
module Model where

import ClassyPrelude.Yesod
import Database.Persist.Quasi

import ModelTypes
import Yesod.Auth.HashDB (HashDBUser(..))

-- You can define all of your database entities in the entities file.
-- You can find more information on persistent and how to declare entities
-- at:
-- http://www.yesodweb.com/book/persistent/
share [mkPersist sqlSettings, mkMigrate "migrateAll"]
    $(persistFileWith lowerCaseSettings "config/models")

instance HashDBUser User where
    userPasswordHash = Just . userPassword
    userPasswordSalt = Just . userSalt
    setPasswordHash h p = p { userSalt     = ""
                            , userPassword = h
                            }
