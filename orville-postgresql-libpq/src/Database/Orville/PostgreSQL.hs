{- |
Module    : Database.Orville.PostgreSQL.Raw
Copyright : Flipstone Technology Partners 2020-2021
License   : MIT
-}
module Database.Orville.PostgreSQL
  ( createConnectionPool,
    SqlType
      ( SqlType,
        sqlTypeExpr,
        sqlTypeReferenceExpr,
        sqlTypeNullable,
        sqlTypeId,
        sqlTypeSqlSize,
        sqlTypeToSql,
        sqlTypeFromSql
      ),
    -- numeric types
    integer,
    serial,
    bigInteger,
    bigSerial,
    double,
    -- textual-ish types
    boolean,
    unboundedText,
    fixedText,
    boundedText,
    textSearchVector,
    -- date types
    date,
    timestamp,
    -- type conversions
    nullableType,
    foreignRefType,
    convertSqlType,
    maybeConvertSqlType,
    Expr.QueryExpr,
  )
where

import Database.Orville.PostgreSQL.Connection (createConnectionPool)
import qualified Database.Orville.PostgreSQL.Internal.Expr as Expr
import Database.Orville.PostgreSQL.Internal.SqlType
  ( SqlType
      ( SqlType,
        sqlTypeExpr,
        sqlTypeFromSql,
        sqlTypeId,
        sqlTypeNullable,
        sqlTypeReferenceExpr,
        sqlTypeSqlSize,
        sqlTypeToSql
      ),
    bigInteger,
    bigSerial,
    boolean,
    boundedText,
    convertSqlType,
    date,
    double,
    fixedText,
    foreignRefType,
    integer,
    maybeConvertSqlType,
    nullableType,
    serial,
    textSearchVector,
    timestamp,
    unboundedText,
  )