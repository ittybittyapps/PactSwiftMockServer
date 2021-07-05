//
//  Created by Marko Justinek on 10/5/21.
//  Copyright © 2020 Marko Justinek. All rights reserved.
//
//  Permission to use, copy, modify, and/or distribute this software for any
//  purpose with or without fee is hereby granted, provided that the above
//  copyright notice and this permission notice appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
//  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
//  SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
//  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
//  IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//

import Foundation
@_implementationOnly import PactSwiftToolbox

public class MockServer {

	// MARK: - Properties

	/// The URL on which MockServer is running.
	public var baseUrl: String {
		"\(transferProtocol.protocol)://\(socketAddress):\(port)"
	}

	let socketAddress = "0.0.0.0"
	let port: Int32
	var transferProtocol: TransferProtocol = .standard
	var tls: Bool {
		transferProtocol == .secure ? true : false
	}

	// MARK: - Lifecycle

	/// Initializes a MockServer on a given port. If none is provided a random unused port will be used
	public init(port: Int? = nil) {
		if let port = port {
			self.port = Int32(port)
		} else {
			self.port = SocketBinder.unusedPort()
		}
	}

	deinit {
		shutdownMockServer()
	}

	// MARK: - Interface

	/// Spin up a Mock Server with expected interactions as defined in Pact.
	public func setup(pact: Data, protocol: TransferProtocol = .standard, completion: (Result<Int, MockServerError>) -> Void) {
		Logger.log(message: "Setting up libpact_mock_server", data: pact)
		transferProtocol = `protocol`
		Logger.log(message: "Setting up MockServer for Pact interaction test")
		let mockServerPort = create_mock_server(
			String(data: pact, encoding: .utf8),
			"\(socketAddress):\(port)",
			tls
		)

		Logger.log(message: "MockServer started on port \(mockServerPort)")
		return (mockServerPort > 1_200)
			? completion(Result.success(Int(mockServerPort)))
			: completion(Result.failure(MockServerError(code: Int(mockServerPort))))
	}

	/// Verify interactions
	public func verify(completion: (Result<Bool, VerificationError>) -> Void) {
		guard requestsMatched else {
			completion(.failure(.reason(mismatchDescription)))
			return
		}
		completion(.success(true))
	}

	/// Finalise tests by writing the contract file onto disk
	public func finalize(pact: Data, completion: ((Result<String, MockServerError>) -> Void)?) {
		Logger.log(message: "Starting up MockServer to finalize writing Pact with data:", data: pact)

		let newPort = SocketBinder.unusedPort()
		Logger.log(message: "Creating MockServer on port \(newPort)")
		let port = create_mock_server(
			String(data: pact, encoding: .utf8)?.replacingOccurrences(of: "\\", with: ""),
			"\(socketAddress):\(newPort)",
			tls
		)
		Logger.log(message: "Created a MockServer on port \(port) to write a Pact contract file")

		writePactContractFile(port: port) {
			switch $0 {
			case .success(let message):
				completion?(.success(message))
			case .failure(let error):
				completion?(.failure(error))
			}
		}

		shutdownMockServer()
	}

	/// Generates an example string based on the provided regex.
	public static func generate_value(regex: String) -> String? {
		guard let stringPointer = generate_regex_value(regex).ok._0 else {
			return nil
		}

		return String(cString: stringPointer)
	}

}

private extension MockServer {

	/// `true` when all expected requests have successfully matched
	var requestsMatched: Bool {
		mock_server_matched(port)
	}

	/// Descripton of mismatching requests
	var mismatchDescription: String {
		guard let mismatches = mock_server_mismatches(port) else {
			return "No response! There might be something fishy going on with your Mock Server..."
		}

		let errorDescription = VerificationErrorHandler(mismatches: String(cString: mismatches)).description
		return errorDescription
	}

	/// Writes the Pact file to disk
	func writePactContractFile(port: Int32? = nil, completion: (Result<String, MockServerError>) -> Void) {
		guard PactFileManager.isPactDirectoryAvailable() else {
			completion(.failure(.failedToWriteFile))
			return
		}

		let pactDir = PactFileManager.pactDirectoryPath
		Logger.log(message: "Writing Pact contract in \(pactDir) using MockServer on port: \(port ?? self.port)")
		let writeResult = write_pact_file(port ?? self.port, pactDir)
		guard writeResult == 0 else {
			completion(.failure(MockServerError(code: Int(writeResult))))
			return
		}
		completion(.success("Pact written to \(pactDir)"))
	}

	/// Shuts down the MockServer and releases the socket address
	func shutdownMockServer(on port: Int32? = nil) {
		let port = port ?? self.port
		if port > 0 {
			Logger.log(message: "Shutting down mock server on port \(port)")
			cleanup_mock_server(port)
		}
	}

}
