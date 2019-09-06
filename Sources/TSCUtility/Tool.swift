/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import TSCLibc

public protocol Option {
    init()
}

public protocol ToolName {
    static var toolName: String { get }
}

/// Handler for the main DiagnosticsEngine used by the SwiftTool class.
private final class DiagnosticsEngineHandler {
    
    /// The standard output stream.
    var stdoutStream = TSCBasic.stdoutStream
    
    /// The default instance.
    static let `default` = DiagnosticsEngineHandler()
    
    private init() {}
    
    func diagnosticsHandler(_ diagnostic: Diagnostic) {
        print(diagnostic: diagnostic, stdoutStream: stderrStream)
    }
}

/// An enum indicating the execution status of run commands.
public enum ExecutionStatus {
    case success
    case failure
}

public protocol CommandLineArgumentDefinition {
    associatedtype Options: Option
    static func postprocessArgParserResult(result: ArgumentParser.Result, diagnostics: DiagnosticsEngine) throws
    static func defineArguments(parser: ArgumentParser, binder: ArgumentBinder<Options>)
}

public protocol CommandLineTool: class {
    associatedtype Options: Option
    
    var base: CommandLineToolBase<Options> { get }
    func runImpl() throws
}

public extension CommandLineTool {
    var options: Options { return base.options }
    var parser: ArgumentParser { return base.parser }
    var originalWorkingDirectory: AbsolutePath { return base.originalWorkingDirectory }
    var diagnostics: DiagnosticsEngine { return base.diagnostics }
    var stdoutStream: OutputByteStream { return base.stdoutStream }
    var executionStatus: ExecutionStatus {
        get { return base.executionStatus }
        set { base.executionStatus = newValue }
    }
    static func exit(with status: ExecutionStatus) -> Never {
        return CommandLineToolBase<Options>.exit(with: status)
    }
    func redirectStdoutToStderr() {
        base.redirectStdoutToStderr()
    }
    
    /// Execute the tool.
    func run() {
        do {
            // Call the implementation.
            try runImpl()
            if diagnostics.hasErrors {
                throw Diagnostics.fatalError
            }
        } catch {
            // Set execution status to failure in case of errors.
            executionStatus = .failure
            handle(error: error)
        }
        Self.exit(with: executionStatus)
    }
}

open class CommandLineToolBase<Options: Option> {
    
    /// The options of this tool.
    public let options: Options
    
    /// The original working directory.
    public let originalWorkingDirectory: AbsolutePath
    
    /// Reference to the argument parser.
    public let parser: ArgumentParser
    
    /// The diagnostics engine.
    public let diagnostics: DiagnosticsEngine = DiagnosticsEngine(
        handlers: [DiagnosticsEngineHandler.default.diagnosticsHandler])
    
    /// The stream to print standard output on.
    public fileprivate(set) var stdoutStream: OutputByteStream = TSCBasic.stdoutStream
    
    /// The execution status of the tool.
    public var executionStatus: ExecutionStatus = .success
    
    public init<A: CommandLineArgumentDefinition>(argumentDefinition: A.Type, toolName: String, usage: String, overview: String, args: [String], seeAlso: String? = nil) where A.Options == Options {
        // Capture the original working directory ASAP.
        guard let cwd = localFileSystem.currentWorkingDirectory else {
            diagnostics.emit(error: "couldn't determine the current working directory")
            type(of: self).exit(with: .failure)
        }
        originalWorkingDirectory = cwd

        // Create the parser.
        parser = ArgumentParser(
            commandName: "swift \(toolName)",
            usage: usage,
            overview: overview,
            seeAlso: seeAlso)
        
        // Create the binder.
        let binder = ArgumentBinder<Options>()
        
        // Let subclasses bind arguments.
        argumentDefinition.defineArguments(parser: parser, binder: binder)
        
        do {
            // Parse the result.
            let result = try parser.parse(args)
            
            try argumentDefinition.postprocessArgParserResult(result: result, diagnostics: diagnostics)
            
            var options = Options()
            try binder.fill(parseResult: result, into: &options)
            
            self.options = options
        } catch {
            handle(error: error)
            type(of: self).exit(with: .failure)
        }
    }
    
    /// Start redirecting the standard output stream to the standard error stream.
    public func redirectStdoutToStderr() {
        self.stdoutStream = TSCBasic.stderrStream
        DiagnosticsEngineHandler.default.stdoutStream = TSCBasic.stderrStream
    }
    
    /// Exit the tool with the given execution status.
    public static func exit(with status: ExecutionStatus) -> Never {
        switch status {
        case .success: TSCLibc.exit(0)
        case .failure: TSCLibc.exit(1)
        }
    }
    
}
