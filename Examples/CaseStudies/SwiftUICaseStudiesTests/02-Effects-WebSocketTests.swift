import Combine
import ComposableArchitecture
import XCTest

@testable import SwiftUICaseStudies

@MainActor
class WebSocketTests: XCTestCase {
  func testWebSocketHappyPath() async {
    let actions = AsyncStream<WebSocketClient.Action>.streamWithContinuation()
    let messages = AsyncStream<TaskResult<WebSocketClient.Message>>.streamWithContinuation()

    var webSocket = WebSocketClient.failing
    webSocket.open = { _, _, _ in actions.stream }
    webSocket.send = { _, _ in }
    webSocket.receive = { _ in messages.stream }
    webSocket.sendPing = { _ in try await Task.never() }

    let store = TestStore(
      initialState: .init(),
      reducer: WebSocket()
        .dependency(\.mainQueue, .immediate)
        .dependency(\.webSocket, webSocket)
    )

    // Connect to the socket
    store.send(.connectButtonTapped) {
      $0.connectivityState = .connecting
    }
    actions.continuation.yield(.didOpen(protocol: nil))
    await store.receive(.webSocket(.didOpen(protocol: nil))) {
      $0.connectivityState = .connected
    }

    // Receive a message
    messages.continuation.yield(.success(.string("Welcome to echo.pointfree.co")))
    await store.receive(.receivedSocketMessage(.success(.string("Welcome to echo.pointfree.co")))) {
      $0.receivedMessages = ["Welcome to echo.pointfree.co"]
    }

    // Send a message
    store.send(.messageToSendChanged("Hi")) {
      $0.messageToSend = "Hi"
    }
    store.send(.sendButtonTapped) {
      $0.messageToSend = ""
    }
    await store.receive(.sendResponse(didSucceed: true))

    // Receive a message
    messages.continuation.yield(.success(.string("Hi")))
    await store.receive(.receivedSocketMessage(.success(.string("Hi")))) {
      $0.receivedMessages = ["Welcome to echo.pointfree.co", "Hi"]
    }

    // Disconnect from the socket
    store.send(.connectButtonTapped) {
      $0.connectivityState = .disconnected
    }
  }

  func testWebSocketSendFailure() async {
    let actions = AsyncStream<WebSocketClient.Action>.streamWithContinuation()
    let messages = AsyncStream<TaskResult<WebSocketClient.Message>>.streamWithContinuation()

    var webSocket = WebSocketClient.failing
    webSocket.open = { _, _, _ in actions.stream }
    webSocket.receive = { _ in messages.stream }
    webSocket.send = { _, _ in
      struct SendFailure: Error, Equatable {}
      throw SendFailure()
    }
    webSocket.sendPing = { _ in try await Task.never() }

    let store = TestStore(
      initialState: .init(),
      reducer: WebSocket()
        .dependency(\.mainQueue, .immediate)
        .dependency(\.webSocket, webSocket)
    )

    // Connect to the socket
    store.send(.connectButtonTapped) {
      $0.connectivityState = .connecting
    }
    actions.continuation.yield(.didOpen(protocol: nil))
    await store.receive(.webSocket(.didOpen(protocol: nil))) {
      $0.connectivityState = .connected
    }

    // Send a message
    store.send(.messageToSendChanged("Hi")) {
      $0.messageToSend = "Hi"
    }
    store.send(.sendButtonTapped) {
      $0.messageToSend = ""
    }
    await store.receive(.sendResponse(didSucceed: false)) {
      $0.alert = .init(title: .init("Could not send socket message. Try again."))
    }

    // Disconnect from the socket
    store.send(.connectButtonTapped) {
      $0.connectivityState = .disconnected
    }
  }

  func testWebSocketPings() async {
    let actions = AsyncStream<WebSocketClient.Action>.streamWithContinuation()
    let pingsCount = SendableState(0)

    var webSocket = WebSocketClient.failing
    webSocket.open = { _, _, _ in actions.stream }
    webSocket.receive = { _ in try await Task.never() }
    webSocket.sendPing = { _ in await pingsCount.modify { $0 += 1 } }

    let mainQueue = DispatchQueue.test
    let store = TestStore(
      initialState: .init(),
      reducer: WebSocket()
        .dependency(\.mainQueue, mainQueue.eraseToAnyScheduler())
        .dependency(\.webSocket, webSocket)
    )

    // Connect to the socket
    store.send(.connectButtonTapped) {
      $0.connectivityState = .connecting
    }
    actions.continuation.yield(.didOpen(protocol: nil))
    await store.receive(.webSocket(.didOpen(protocol: nil))) {
      $0.connectivityState = .connected
    }

    // Wait for ping
    let before = await pingsCount.value
    XCTAssertEqual(before, 0)
    await mainQueue.advance(by: .seconds(10))
    let after = await pingsCount.value
    XCTAssertEqual(after, 1)

    // Disconnect from the socket
    store.send(.connectButtonTapped) {
      $0.connectivityState = .disconnected
    }
  }

  func testWebSocketConnectError() async {
    let actions = AsyncStream<WebSocketClient.Action>.streamWithContinuation()

    var webSocket = WebSocketClient.failing
    webSocket.open = { _, _, _ in actions.stream }
    webSocket.receive = { _ in try await Task.never() }
    webSocket.sendPing = { _ in try await Task.never() }

    let store = TestStore(
      initialState: .init(),
      reducer: WebSocket()
        .dependency(\.mainQueue, .immediate)
        .dependency(\.webSocket, webSocket)
    )

    // Attempt to connect to the socket
    store.send(.connectButtonTapped) {
      $0.connectivityState = .connecting
    }
    actions.continuation.yield(.didClose(code: .internalServerError, reason: nil))
    await store.receive(.webSocket(.didClose(code: .internalServerError, reason: nil))) {
      $0.connectivityState = .disconnected
    }
  }
}
