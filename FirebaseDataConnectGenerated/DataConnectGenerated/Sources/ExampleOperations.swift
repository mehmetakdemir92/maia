import Foundation

import FirebaseCore
import FirebaseDataConnect




















// MARK: Common Enums

public enum OrderDirection: String, Codable, Sendable {
  case ASC = "ASC"
  case DESC = "DESC"
  }

public enum SearchQueryFormat: String, Codable, Sendable {
  case QUERY = "QUERY"
  case PLAIN = "PLAIN"
  case PHRASE = "PHRASE"
  case ADVANCED = "ADVANCED"
  }


// MARK: Connector Enums

// End enum definitions









public class CreateUserMutationMutation{

  let dataConnect: DataConnect

  init(dataConnect: DataConnect) {
    self.dataConnect = dataConnect
  }

  public static let OperationName = "CreateUserMutation"

  public typealias Ref = MutationRef<CreateUserMutationMutation.Data,CreateUserMutationMutation.Variables>

  public struct Variables: OperationVariable {
  
        
        public var
displayName: String

  
        @OptionalVariable
        public var
email: String?

  
        @OptionalVariable
        public var
profilePictureUrl: String?


    
    
    
    public init (
        
displayName: String

        
        
        ,
        _ optionalVars: ((inout Variables)->())? = nil
        ) {
        self.displayName = displayName
        

        
        if let optionalVars {
            optionalVars(&self)
        }
        
    }

    public static func == (lhs: Variables, rhs: Variables) -> Bool {
      
        return lhs.displayName == rhs.displayName && 
              lhs.email == rhs.email && 
              lhs.profilePictureUrl == rhs.profilePictureUrl
              
    }

    
public func hash(into hasher: inout Hasher) {
  
  hasher.combine(displayName)
  
  hasher.combine(email)
  
  hasher.combine(profilePictureUrl)
  
}

    enum CodingKeys: String, CodingKey {
      
      case displayName
      
      case email
      
      case profilePictureUrl
      
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      let codecHelper = CodecHelper<CodingKeys>()
      
      
      try codecHelper.encode(displayName, forKey: .displayName, container: &container)
      
      
      if $email.isSet { 
      try codecHelper.encode(email, forKey: .email, container: &container)
      }
      
      if $profilePictureUrl.isSet { 
      try codecHelper.encode(profilePictureUrl, forKey: .profilePictureUrl, container: &container)
      }
      
    }

  }

  public struct Data: Decodable, Sendable {



public var 
user_insert: UserKey

  }

  public func ref(
        
displayName: String

        
        ,
        _ optionalVars: ((inout CreateUserMutationMutation.Variables)->())? = nil
        ) -> MutationRef<CreateUserMutationMutation.Data,CreateUserMutationMutation.Variables>  {
        var variables = CreateUserMutationMutation.Variables(displayName:displayName)
        
        if let optionalVars {
            optionalVars(&variables)
        }
        

        let ref = dataConnect.mutation(name: "CreateUserMutation", variables: variables, resultsDataType:CreateUserMutationMutation.Data.self)
        return ref as MutationRef<CreateUserMutationMutation.Data,CreateUserMutationMutation.Variables>
   }

  @MainActor
   public func execute(
        
displayName: String

        
        ,
        _ optionalVars: (@MainActor (inout CreateUserMutationMutation.Variables)->())? = nil
        ) async throws -> OperationResult<CreateUserMutationMutation.Data> {
        var variables = CreateUserMutationMutation.Variables(displayName:displayName)
        
        if let optionalVars {
            optionalVars(&variables)
        }
        
        
        let ref = dataConnect.mutation(name: "CreateUserMutation", variables: variables, resultsDataType:CreateUserMutationMutation.Data.self)
        
        return try await ref.execute()
        
   }
}






public class GetEntriesByUserQuery{

  let dataConnect: DataConnect

  init(dataConnect: DataConnect) {
    self.dataConnect = dataConnect
  }

  public static let OperationName = "GetEntriesByUser"

  public typealias Ref = QueryRefObservation<GetEntriesByUserQuery.Data,GetEntriesByUserQuery.Variables>

  public struct Variables: OperationVariable {
  
        
        public var
userId: UUID


    
    
    
    public init (
        
userId: UUID

        
        ) {
        self.userId = userId
        

        
    }

    public static func == (lhs: Variables, rhs: Variables) -> Bool {
      
        return lhs.userId == rhs.userId
              
    }

    
public func hash(into hasher: inout Hasher) {
  
  hasher.combine(userId)
  
}

    enum CodingKeys: String, CodingKey {
      
      case userId
      
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      let codecHelper = CodecHelper<CodingKeys>()
      
      
      try codecHelper.encode(userId, forKey: .userId, container: &container)
      
      
    }

  }

  public struct Data: Decodable, Sendable {




public struct Entry: Decodable, Sendable ,Hashable, Equatable, Identifiable {
  


public var 
id: UUID



public var 
content: String



public var 
createdAt: Timestamp



public var 
date: LocalDate



public var 
isHighlight: Bool?



public var 
updatedAt: Timestamp


  
  public var entryKey: EntryKey {
    return EntryKey(
      
      id: id
    )
  }

  
public func hash(into hasher: inout Hasher) {
  
  hasher.combine(id)
  
}
public static func == (lhs: Entry, rhs: Entry) -> Bool {
    
    return lhs.id == rhs.id 
        
  }

  

  
  enum CodingKeys: String, CodingKey {
    
    case id
    
    case content
    
    case createdAt
    
    case date
    
    case isHighlight
    
    case updatedAt
    
  }

  public init(from decoder: any Decoder) throws {
    var container = try decoder.container(keyedBy: CodingKeys.self)
    let codecHelper = CodecHelper<CodingKeys>()

    
    
    self.id = try codecHelper.decode(UUID.self, forKey: .id, container: &container)
    
    
    
    self.content = try codecHelper.decode(String.self, forKey: .content, container: &container)
    
    
    
    self.createdAt = try codecHelper.decode(Timestamp.self, forKey: .createdAt, container: &container)
    
    
    
    self.date = try codecHelper.decode(LocalDate.self, forKey: .date, container: &container)
    
    
    
    self.isHighlight = try codecHelper.decode(Bool?.self, forKey: .isHighlight, container: &container)
    
    
    
    self.updatedAt = try codecHelper.decode(Timestamp.self, forKey: .updatedAt, container: &container)
    
    
  }
}
public var 
entries: [Entry]

  }

  public func ref(
        
userId: UUID

        ) -> QueryRefObservation<GetEntriesByUserQuery.Data,GetEntriesByUserQuery.Variables>  {
        var variables = GetEntriesByUserQuery.Variables(userId:userId)
        

        let ref = dataConnect.query(name: "GetEntriesByUser", variables: variables, resultsDataType:GetEntriesByUserQuery.Data.self, publisher: .observableMacro)
        return ref as! QueryRefObservation<GetEntriesByUserQuery.Data,GetEntriesByUserQuery.Variables>
   }

  @MainActor
   public func execute(
        
userId: UUID

        ) async throws -> OperationResult<GetEntriesByUserQuery.Data> {
        var variables = GetEntriesByUserQuery.Variables(userId:userId)
        
        
        let ref = dataConnect.query(name: "GetEntriesByUser", variables: variables, resultsDataType:GetEntriesByUserQuery.Data.self, publisher: .observableMacro)
        
        let refCast = ref as! QueryRefObservation<GetEntriesByUserQuery.Data,GetEntriesByUserQuery.Variables>
        return try await refCast.execute()
        
   }
}






public class CreateTagMutation{

  let dataConnect: DataConnect

  init(dataConnect: DataConnect) {
    self.dataConnect = dataConnect
  }

  public static let OperationName = "CreateTag"

  public typealias Ref = MutationRef<CreateTagMutation.Data,CreateTagMutation.Variables>

  public struct Variables: OperationVariable {
  
        
        public var
name: String


    
    
    
    public init (
        
name: String

        
        ) {
        self.name = name
        

        
    }

    public static func == (lhs: Variables, rhs: Variables) -> Bool {
      
        return lhs.name == rhs.name
              
    }

    
public func hash(into hasher: inout Hasher) {
  
  hasher.combine(name)
  
}

    enum CodingKeys: String, CodingKey {
      
      case name
      
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      let codecHelper = CodecHelper<CodingKeys>()
      
      
      try codecHelper.encode(name, forKey: .name, container: &container)
      
      
    }

  }

  public struct Data: Decodable, Sendable {



public var 
tag_insert: TagKey

  }

  public func ref(
        
name: String

        ) -> MutationRef<CreateTagMutation.Data,CreateTagMutation.Variables>  {
        var variables = CreateTagMutation.Variables(name:name)
        

        let ref = dataConnect.mutation(name: "CreateTag", variables: variables, resultsDataType:CreateTagMutation.Data.self)
        return ref as MutationRef<CreateTagMutation.Data,CreateTagMutation.Variables>
   }

  @MainActor
   public func execute(
        
name: String

        ) async throws -> OperationResult<CreateTagMutation.Data> {
        var variables = CreateTagMutation.Variables(name:name)
        
        
        let ref = dataConnect.mutation(name: "CreateTag", variables: variables, resultsDataType:CreateTagMutation.Data.self)
        
        return try await ref.execute()
        
   }
}






public class ListAllTagsQuery{

  let dataConnect: DataConnect

  init(dataConnect: DataConnect) {
    self.dataConnect = dataConnect
  }

  public static let OperationName = "ListAllTags"

  public typealias Ref = QueryRefObservation<ListAllTagsQuery.Data,ListAllTagsQuery.Variables>

  public struct Variables: OperationVariable {

    
    
  }

  public struct Data: Decodable, Sendable {




public struct Tag: Decodable, Sendable ,Hashable, Equatable, Identifiable {
  


public var 
id: UUID



public var 
name: String


  
  public var tagKey: TagKey {
    return TagKey(
      
      id: id
    )
  }

  
public func hash(into hasher: inout Hasher) {
  
  hasher.combine(id)
  
}
public static func == (lhs: Tag, rhs: Tag) -> Bool {
    
    return lhs.id == rhs.id 
        
  }

  

  
  enum CodingKeys: String, CodingKey {
    
    case id
    
    case name
    
  }

  public init(from decoder: any Decoder) throws {
    var container = try decoder.container(keyedBy: CodingKeys.self)
    let codecHelper = CodecHelper<CodingKeys>()

    
    
    self.id = try codecHelper.decode(UUID.self, forKey: .id, container: &container)
    
    
    
    self.name = try codecHelper.decode(String.self, forKey: .name, container: &container)
    
    
  }
}
public var 
tags: [Tag]

  }

  public func ref(
        
        ) -> QueryRefObservation<ListAllTagsQuery.Data,ListAllTagsQuery.Variables>  {
        var variables = ListAllTagsQuery.Variables()
        

        let ref = dataConnect.query(name: "ListAllTags", variables: variables, resultsDataType:ListAllTagsQuery.Data.self, publisher: .observableMacro)
        return ref as! QueryRefObservation<ListAllTagsQuery.Data,ListAllTagsQuery.Variables>
   }

  @MainActor
   public func execute(
        
        ) async throws -> OperationResult<ListAllTagsQuery.Data> {
        var variables = ListAllTagsQuery.Variables()
        
        
        let ref = dataConnect.query(name: "ListAllTags", variables: variables, resultsDataType:ListAllTagsQuery.Data.self, publisher: .observableMacro)
        
        let refCast = ref as! QueryRefObservation<ListAllTagsQuery.Data,ListAllTagsQuery.Variables>
        return try await refCast.execute()
        
   }
}


