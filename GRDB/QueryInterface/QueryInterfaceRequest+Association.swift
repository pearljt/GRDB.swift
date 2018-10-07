extension QueryInterfaceRequest where RowDecoder: TableRecord {
    func joining<A: Association>(_ joinOperator: AssociationJoinOperator, _ association: A)
        -> QueryInterfaceRequest<RowDecoder>
        where A.OriginRowDecoder == RowDecoder
    {
        let join = AssociationJoin(
            joinOperator: joinOperator,
            joinCondition: association.joinCondition,
            query: association.request.query)
        return QueryInterfaceRequest(query: query.appendingJoin(join, forKey: association.key))
    }
    
    // MARK: - Associations
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are selected. The returned association does not
    /// require that the associated database table contains a matching row.
    public func including<A: Association>(optional association: A) -> QueryInterfaceRequest<RowDecoder> where A.OriginRowDecoder == RowDecoder {
        return joining(.optional, association)
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are selected. The returned association requires
    /// that the associated database table contains a matching row.
    public func including<A: Association>(required association: A) -> QueryInterfaceRequest<RowDecoder> where A.OriginRowDecoder == RowDecoder {
        return joining(.required, association)
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are not selected. The returned association does not
    /// require that the associated database table contains a matching row.
    public func joining<A: Association>(optional association: A) -> QueryInterfaceRequest<RowDecoder> where A.OriginRowDecoder == RowDecoder {
        return joining(.optional, association.select([]))
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are not selected. The returned association requires
    /// that the associated database table contains a matching row.
    public func joining<A: Association>(required association: A) -> QueryInterfaceRequest<RowDecoder> where A.OriginRowDecoder == RowDecoder {
        return joining(.required, association.select([]))
    }
    
    // MARK: - Association Aggregates
    
    /// TODO
    public func annotated<A: Association>(with aggregate: AssociationAggregate<A>) -> QueryInterfaceRequest<RowDecoder> where A.OriginRowDecoder == RowDecoder {
        // SELECT author.*, COUNT(book.rowID) AS bookCount
        // LEFT JOIN book ON ...
        // GROUP BY author.id
        let tableAlias = TableAlias()
        let selectable: SQLSelectable
        if let alias = aggregate.alias {
            selectable = tableAlias[aggregate.expression].aliased(alias)
        } else {
            selectable = tableAlias[aggregate.expression]
        }
        return appendingSelection([selectable])
            .joining(optional: aggregate.association.aliased(tableAlias))
            .groupByPrimaryKey()
    }
    
    /// TODO
    public func having<A: Association>(_ aggregate: AssociationAggregate<A>) -> QueryInterfaceRequest<T> where A.OriginRowDecoder == RowDecoder {
        // SELECT author.*
        // LEFT JOIN book ON ...
        // GROUP BY author.id
        // HAVING COUNT(book.rowID) > 0
        let tableAlias = TableAlias()
        return having(tableAlias[aggregate.expression])
            .joining(optional: aggregate.association.aliased(tableAlias))
            .groupByPrimaryKey()
    }
}

extension MutablePersistableRecord {
    /// Creates a request that fetches the associated record(s).
    ///
    /// For example:
    ///
    ///     struct Team: {
    ///         static let players = hasMany(Player.self)
    ///         var players: QueryInterfaceRequest<Player> {
    ///             return request(for: Team.players)
    ///         }
    ///     }
    ///
    ///     let team: Team = ...
    ///     let players = try team.players.fetchAll(db) // [Player]
    public func request<A: Association>(for association: A) -> QueryInterfaceRequest<A.RowDecoder> where A.OriginRowDecoder == Self {
        return association.request(from: self)
    }
}

extension TableRecord {
    
    // MARK: - Associations
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are selected. The returned association does not
    /// require that the associated database table contains a matching row.
    public static func including<A: Association>(optional association: A) -> QueryInterfaceRequest<Self> where A.OriginRowDecoder == Self {
        return all().including(optional: association)
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are selected. The returned association requires
    /// that the associated database table contains a matching row.
    public static func including<A: Association>(required association: A) -> QueryInterfaceRequest<Self> where A.OriginRowDecoder == Self {
        return all().including(required: association)
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are not selected. The returned association does not
    /// require that the associated database table contains a matching row.
    public static func joining<A: Association>(optional association: A) -> QueryInterfaceRequest<Self> where A.OriginRowDecoder == Self {
        return all().joining(optional: association)
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are not selected. The returned association requires
    /// that the associated database table contains a matching row.
    public static func joining<A: Association>(required association: A) -> QueryInterfaceRequest<Self> where A.OriginRowDecoder == Self {
        return all().joining(required: association)
    }
    
    // MARK: - Association Aggregates
    
    /// TODO
    public static func annotated<A: Association>(with aggregate: AssociationAggregate<A>) -> QueryInterfaceRequest<Self> where A.OriginRowDecoder == Self {
        return all().annotated(with: aggregate)
    }
    
    /// TODO
    public static func having<A: Association>(_ aggregate: AssociationAggregate<A>) -> QueryInterfaceRequest<Self> where A.OriginRowDecoder == Self {
        return all().having(aggregate)
    }
}
