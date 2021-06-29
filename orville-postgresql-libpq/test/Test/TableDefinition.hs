module Test.TableDefinition
  ( tableDefinitionProperties,
  )
where

import qualified Control.Exception as E
import qualified Control.Monad.IO.Class as MIO
import qualified Data.ByteString.Char8 as B8
import qualified Data.List.NonEmpty as NEL
import qualified Data.Pool as Pool
import qualified Data.String as String
import qualified Hedgehog as HH

import qualified Database.Orville.PostgreSQL.Connection as Conn
import qualified Database.Orville.PostgreSQL.Internal.Expr as Expr
import qualified Database.Orville.PostgreSQL.Internal.RawSql as RawSql
import qualified Database.Orville.PostgreSQL.Internal.SqlMarshaller as SqlMarshaller
import qualified Database.Orville.PostgreSQL.Internal.TableDefinition as TableDefinition

import qualified Test.Entities.Foo as Foo
import qualified Test.Property as Property
import qualified Test.TestTable as TestTable

tableDefinitionProperties :: Pool.Pool Conn.Connection -> IO Bool
tableDefinitionProperties pool =
  HH.checkSequential $
    HH.Group
      (String.fromString "TableDefinition")
      [
        ( String.fromString "Creates a table than can round trip an entity through it"
        , HH.property $ do
            originalFoo <- HH.forAll Foo.generate

            let insertFoo =
                  TableDefinition.mkInsertExpr Foo.table (originalFoo NEL.:| [])

                selectFoos =
                  TableDefinition.mkQueryExpr Foo.table Nothing Nothing

            foosFromDB <-
              MIO.liftIO . Pool.withResource pool $ \connection -> do
                TestTable.dropAndRecreateTableDef connection Foo.table
                RawSql.executeVoid connection (Expr.insertExprToSql insertFoo)
                result <- RawSql.execute connection (Expr.queryExprToSql selectFoos)
                SqlMarshaller.marshallResultFromSql (TableDefinition.tableMarshaller Foo.table) result

            foosFromDB HH.=== Right [originalFoo]
        )
      ,
        ( String.fromString "Creates a primary key that rejects duplicate records"
        , Property.singletonProperty $ do
            originalFoo <- HH.forAll Foo.generate

            let insertFoo =
                  TableDefinition.mkInsertExpr Foo.table (originalFoo NEL.:| [])

            result <- MIO.liftIO . E.try . Pool.withResource pool $ \connection -> do
              TestTable.dropAndRecreateTableDef connection Foo.table
              RawSql.executeVoid connection (Expr.insertExprToSql insertFoo)
              RawSql.executeVoid connection (Expr.insertExprToSql insertFoo)

            case result of
              Right () -> do
                HH.footnote "Expected 'executeVoid' to return failure, but it did not"
                HH.failure
              Left err ->
                Conn.sqlExecutionErrorSqlState err HH.=== Just (B8.pack "23505")
        )
      ]
