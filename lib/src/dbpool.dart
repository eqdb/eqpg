// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

class DbConnection {
  final String _dbHost, _dbName, _dbUser, _dbPass;
  final int _dbPort;

  DbConnection(
      this._dbHost, this._dbPort, this._dbName, this._dbUser, this._dbPass);

  Future<PostgreSQLConnection> create() async {
    final connection = new PostgreSQLConnection(_dbHost, _dbPort, _dbName,
        username: _dbUser, password: _dbPass);
    await connection.open();
    return connection;
  }
}

typedef Future _ConnectionHandler(PostgreSQLConnection connection);
typedef Future TransactionHandler(PostgreSQLExecutionContext connection);

class DbPool {
  final DbConnection _connection;
  int connectionSpace;
  final available = new List<PostgreSQLConnection>();
  final log = new Logger('DbPool');

  DbPool(this._connection, this.connectionSpace);

  /// TODO: close all connections in SIGINT signal.

  Future<List<List>> query(String fmtString,
      [Map<String, dynamic> substitutionValues = null]) async {
    final completer = new Completer<List<List>>();
    _getConnection((connection) async {
      completer.complete(await connection.query(fmtString,
          substitutionValues: substitutionValues));
    }).catchError(completer.completeError);
    return completer.future;
  }

  Future<Null> transaction(TransactionHandler handler) async {
    final completer = new Completer<Null>();
    _getConnection((connection) async {
      // Note: the library automatically rolls back when an exception occurs.
      await connection.transaction(handler);
      completer.complete(null);
    }).catchError(completer.completeError);
    return completer.future;
  }

  Future _getConnection(_ConnectionHandler handler) async {
    // If maxConnections are occupied, throw an error.
    if (connectionSpace == 0 && available.isEmpty) {
      throw new RpcError(503, 'database_busy', 'database is busy');
    } else {
      PostgreSQLConnection connection;
      if (available.isNotEmpty) {
        connection = available.removeLast();
      } else {
        connectionSpace--;
        connection = await _connection.create();
      }

      try {
        await handler(connection);
        available.add(connection);
      } catch (e, stackTrace) {
        // Do not intercept RpcError.
        if (e is RpcError) {
          throw e;
        }

        // Close connection, just in case.
        if (connection != null) {
          connection.close();
        }

        connectionSpace++;

        // Simple method to generate a hash code for this error.
        final hash = '${new DateTime.now()}: $e'.hashCode;

        // Log stack traces and throw a hashed ID.
        log.severe('handler throwed, error hash: $hash', e, stackTrace);
        throw new RpcError(
            500, 'internal_error', 'internal error (ref: $hash)');
      }
    }
  }
}
