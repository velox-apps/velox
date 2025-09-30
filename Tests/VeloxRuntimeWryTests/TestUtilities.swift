import Foundation

func runOnMain<T>(_ work: () throws -> T) throws -> T {
  if Thread.isMainThread {
    return try work()
  }

  var result: Result<T, Error>!
  DispatchQueue.main.sync {
    result = Result { try work() }
  }

  switch result! {
  case .success(let value):
    return value
  case .failure(let error):
    throw error
  }
}
