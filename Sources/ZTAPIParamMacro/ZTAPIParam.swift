// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import ZTAPICore

@attached(member, names: named(key), named(value), arbitrary)
@attached(extension, conformances: ZTAPIParamProtocol)
public macro ZTAPIParam() = #externalMacro(module: "ZTAPIParamMacros", type: "ZTAPIParam")

@attached(peer)
public macro ZTAPIParamKey(_ key: String) = #externalMacro(module: "ZTAPIParamMacros", type: "ZTAPIParamKey")
