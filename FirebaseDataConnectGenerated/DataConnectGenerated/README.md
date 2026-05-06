This Swift package contains the generated Swift code for the connector `example`.

You can use this package by adding it as a local Swift package dependency in your project.

# Accessing the connector

Add the necessary imports

```
import FirebaseDataConnect
import DataConnectGenerated

```

The connector can be accessed using the following code:

```
let connector = DataConnect.exampleConnector

```


## Connecting to the local Emulator
By default, the connector will connect to the production service.

To connect to the emulator, you can use the following code, which can be called from the `init` function of your SwiftUI app

```
connector.useEmulator()
```

# Queries

## GetEntriesByUserQuery
### Variables
#### Required
```swift

let userId: UUID = ...
```




### Using the Query Reference
```
struct MyView: View {
   var getEntriesByUserQueryRef = DataConnect.exampleConnector.getEntriesByUserQuery.ref(...)

  var body: some View {
    VStack {
      if let data = getEntriesByUserQueryRef.data {
        // use data in View
      }
      else {
        Text("Loading...")
      }
    }
    .task {
        do {
          let _ = try await getEntriesByUserQueryRef.execute()
        } catch {
        }
      }
  }
}
```

### One-shot execute
```
DataConnect.exampleConnector.getEntriesByUserQuery.execute(...)
```


## ListAllTagsQuery


### Using the Query Reference
```
struct MyView: View {
   var listAllTagsQueryRef = DataConnect.exampleConnector.listAllTagsQuery.ref(...)

  var body: some View {
    VStack {
      if let data = listAllTagsQueryRef.data {
        // use data in View
      }
      else {
        Text("Loading...")
      }
    }
    .task {
        do {
          let _ = try await listAllTagsQueryRef.execute()
        } catch {
        }
      }
  }
}
```

### One-shot execute
```
DataConnect.exampleConnector.listAllTagsQuery.execute(...)
```


# Mutations
## CreateUserMutationMutation

### Variables

#### Required
```swift

let displayName: String = ...
```
 

#### Optional
```swift

let email: String = ...
let profilePictureUrl: String = ...
```

### One-shot execute
```
DataConnect.exampleConnector.createUserMutationMutation.execute(...)
```

## CreateTagMutation

### Variables

#### Required
```swift

let name: String = ...
```
 

### One-shot execute
```
DataConnect.exampleConnector.createTagMutation.execute(...)
```

