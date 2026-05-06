
import Foundation

import FirebaseCore
import FirebaseDataConnect
public extension DataConnect {

  static let exampleConnector: ExampleConnector = {
    let dc = DataConnect.dataConnect(connectorConfig: ExampleConnector.connectorConfig, callerSDKType: .generated)
    return ExampleConnector(dataConnect: dc)
  }()

}

public class ExampleConnector {

  let dataConnect: DataConnect

  public static let connectorConfig = ConnectorConfig(serviceId: "maia", location: "us-east4", connector: "example")

  init(dataConnect: DataConnect) {
    self.dataConnect = dataConnect

    // init operations 
    self.createUserMutationMutation = CreateUserMutationMutation(dataConnect: dataConnect)
    self.getEntriesByUserQuery = GetEntriesByUserQuery(dataConnect: dataConnect)
    self.createTagMutation = CreateTagMutation(dataConnect: dataConnect)
    self.listAllTagsQuery = ListAllTagsQuery(dataConnect: dataConnect)
    
  }

  public func useEmulator(host: String = DataConnect.EmulatorDefaults.host, port: Int = DataConnect.EmulatorDefaults.port) {
    self.dataConnect.useEmulator(host: host, port: port)
  }

  // MARK: Operations
public let createUserMutationMutation: CreateUserMutationMutation
public let getEntriesByUserQuery: GetEntriesByUserQuery
public let createTagMutation: CreateTagMutation
public let listAllTagsQuery: ListAllTagsQuery


}
