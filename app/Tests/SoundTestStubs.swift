import Foundation
struct AppLanguage { static func choose(_ s:String)->String{s};static func interpolate(_ s:String,_ args:[String])->String{s} }
struct InstallError:Error {enum Code{case unsupported,sourceUnreadable,corrupted,passwordProtected};init(_ code:Code,_ message:String){}}
