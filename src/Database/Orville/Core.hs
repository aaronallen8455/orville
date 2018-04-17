{-|
Module    : Database.Orville.Core
Copyright : Flipstone Technology Partners 2016-2018
License   : MIT
-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}

module Database.Orville.Core
  ( TableDefinition(..)
  , mkTableDefinition
  , tableKeyToSql
  , tableKeyFromSql
  , SqlConversion
  , sqlConversion
  , sqlConvertible
  , sqlConversionVia
  , maybeSqlConversionVia
  , nullableConversion
  , textConversion
  , dayConversion
  , utcTimeConversion
  , intConversion
  , int32Conversion
  , int64Conversion
  , doubleConversion
  , boolConversion
  , TableParams(..)
  , RelationalMap
  , mapAttr
  , mapField
  , attrField
  , maybeMapper
  , prefixMap
  , partialMap
  , readOnlyMap
  , OrvilleEnv
  , newOrvilleEnv
  , ormEnvPool
  , Orville
  , OrvilleT
  , unOrvilleT
  , SqlValue
  , MonadOrville(..)
  , runOrville
  , mapOrvilleT
  , QueryType(..)
  , withTransaction
  , ColumnFlag(..)
  , Now(..)
  , ColumnType(..)
  , FieldDefinition
  , textField
  , fixedTextField
  , dayField
  , utcTimeField
  , int32Field
  , int64Field
  , doubleField
  , boolField
  , automaticIdField
  , searchVectorField
  , nullableField
  , withFlag
  , withName
  , withConversion
  , fieldFromSql
  , SomeField(..)
  , withPrefix
  , fieldName
  , IndexDefinition(..)
  , uniqueIndex
  , simpleIndex
  , ConstraintDefinition(..)
  , uniqueConstraint
  , dropConstraint
  , FromSql
  , FromSqlError(..)
  , ColumnSpecifier(..)
  , col
  , ToSql
  , getField
  , getComponent
  , SchemaItem(..)
  , SchemaDefinition
  , Record
  , CreatedAt
  , UpdatedAt
  , OccurredAt
  , TableComments
  , noComments
  , say
  , WhereCondition
  , whereAnd
  , whereOr
  , whereIn
  , whereNotIn
  , isNull
  , isNotNull
  , (.==)
  , (.<>)
  , (.<-)
  , (%==)
  , (.>)
  , (.>=)
  , (.<)
  , (.<=)
  , SelectOptions(..)
  , where_
  , order
  , limit
  , offset
  , groupBy
  , (<>)
  , FieldUpdate
  , fieldUpdate
  , (.:=)
  , OrderByClause(..)
  , SortDirection(..)
  , migrateSchema
  , selectAll
  , selectFirst
  , deleteRecord
  , deleteWhere
  , findRecord
  , findRecords
  , findRecordsBy
  , insertRecord
  , insertRecordMany
  , updateFields
  , updateRecord
  , MigrationError(..)
  ) where

import Control.Monad.Except
import Control.Monad.Reader
import Control.Monad.State
import Data.Convertible
import qualified Data.Map.Strict as Map
import Data.Maybe (listToMaybe)
import Data.Monoid
import Database.HDBC hiding (withTransaction)

import qualified Data.Map.Helpers as Map
import Database.Orville.Internal.ConstraintDefinition
import Database.Orville.Internal.Execute
import Database.Orville.Internal.FieldDefinition
import Database.Orville.Internal.FieldUpdate
import Database.Orville.Internal.FromSql
import Database.Orville.Internal.GroupBy ()
import Database.Orville.Internal.IndexDefinition
import Database.Orville.Internal.MigrateSchema
import Database.Orville.Internal.Monad
import Database.Orville.Internal.OrderBy
import Database.Orville.Internal.RelationalMap
import Database.Orville.Internal.SelectOptions
import Database.Orville.Internal.Sql
import Database.Orville.Internal.SqlConversion
import Database.Orville.Internal.TableDefinition
import Database.Orville.Internal.Types
import Database.Orville.Internal.Where
import Database.Orville.Raw
import Database.Orville.Select

getField :: Convertible a SqlValue => (entity -> a) -> ToSql entity ()
getField f = do
  value <- asks f
  sqlValues <- get
  put (convert value : sqlValues)

selectAll ::
     TableDefinition entity key -> SelectOptions -> Orville [entity key]
selectAll tableDef = runSelect . selectQueryTable tableDef

selectFirst ::
     TableDefinition entity key
  -> SelectOptions
  -> Orville (Maybe (entity key))
selectFirst tableDef opts =
  listToMaybe <$> selectAll tableDef (limit 1 <> opts)

deleteWhereBuild ::
     TableDefinition entity key -> [WhereCondition] -> Orville Integer
deleteWhereBuild tableDef conds = do
  let deleteSql = mkDeleteClause (tableName tableDef)
  let whereSql = whereClause conds
  let values = whereValues conds
  let querySql = deleteSql ++ " " ++ whereSql
  withConnection $ \conn -> do
    executingSql DeleteQuery querySql $ do run conn querySql values

deleteWhere ::
     TableDefinition entity key -> [WhereCondition] -> Orville Integer
deleteWhere tableDef = deleteWhereBuild tableDef

findRecords ::
     Ord key
  => TableDefinition entity key
  -> [key]
  -> Orville (Map.Map key (entity key))
findRecords _ [] = return Map.empty
findRecords tableDef keys = do
  let keyField = tablePrimaryKey tableDef
      mkEntry record = (tableGetKey tableDef record, record)
  recordList <- selectAll tableDef (where_ $ keyField .<- keys)
  pure $ Map.fromList (map mkEntry recordList)

findRecordsBy ::
     (Ord fieldValue)
  => TableDefinition entity key
  -> FieldDefinition fieldValue
  -> SelectOptions
  -> Orville (Map.Map fieldValue [entity key])
findRecordsBy tableDef field opts = do
  let builder = (,) <$> fieldFromSql field <*> tableFromSql tableDef
      query = selectQuery builder (fromClauseTable tableDef) opts
  Map.groupBy' id <$> runSelect query

findRecord :: TableDefinition entity key -> key -> Orville (Maybe (entity key))
findRecord tableDef key =
  let keyField = tablePrimaryKey tableDef
   in selectFirst tableDef (where_ $ keyField .== key)

updateFields ::
     TableDefinition entity key
  -> [FieldUpdate]
  -> [WhereCondition]
  -> Orville Integer
updateFields tableDef updates conds =
  updateSql (updateClause ++ " " ++ condClause) (updateValues ++ condValues)
  where
    condClause = whereClause conds
    condValues = whereValues conds
    updateValues = map fieldUpdateValue updates
    updateNames = map fieldUpdateName updates
    updateClause = mkUpdateClause (tableName tableDef) updateNames

updateRecord ::
     TableDefinition entity key -> key -> entity anyKey -> Orville (entity key)
updateRecord tableDef key record = do
  let keyField = tablePrimaryKey tableDef
      conds = [keyField .== key]
      isSomeUninsertedField (SomeField f) = isUninsertedField f
      fields = filter (not . isSomeUninsertedField) (tableFields tableDef)
      builder = tableToSql tableDef
      updates = zipWith FieldUpdate fields (runToSql builder record)
  void $ updateFields tableDef updates conds
  pure $ tableSetKey tableDef key record

insertRecord :: TableDefinition entity key -> entity () -> Orville (entity key)
insertRecord tableDef newRecord = do
  let insertSql =
        mkInsertClause (tableName tableDef) (insertableColumnNames tableDef) ++
        " RETURNING id"
      builder = tableToSql tableDef
      vals = runToSql builder newRecord
  rows <-
    withConnection $ \conn -> do
      executingSql InsertQuery insertSql $ do
        insert <- prepare conn insertSql
        void $ execute insert vals
        fetchAllRows' insert
  case rows of
    [[key]] ->
      case tableKeyFromSql tableDef key of
        Just keyValue -> return $ tableSetKey tableDef keyValue newRecord
        _ ->
          error $
          concat
            [ "Found a non-decodeable key in table "
            , tableName tableDef
            , ": "
            , show key
            ]
    [] -> error "Didn't get a key back from the database!"
    _ -> error "Got more than one key back from the database!"

insertRecordMany :: TableDefinition entity key -> [entity ()] -> Orville ()
insertRecordMany tableDef newRecords = do
  let insertSql =
        mkInsertClause (tableName tableDef) (insertableColumnNames tableDef)
  let builder = tableToSql tableDef
  withConnection $ \conn -> do
    executingSql InsertQuery insertSql $ do
      insert <- prepare conn insertSql
      executeMany insert (map (runToSql builder) newRecords)

deleteRecord :: TableDefinition entity key -> entity key -> Orville ()
deleteRecord tableDef record = do
  let keyField = tablePrimaryKey tableDef
      key = tableGetKey tableDef record
  n <- deleteWhere tableDef [keyField .== key]
  if n /= 1
    then error $
         "Expected to delete exactly 1 row for deleteRecord\
               \but actually deleted" ++
         show n
    else pure ()
