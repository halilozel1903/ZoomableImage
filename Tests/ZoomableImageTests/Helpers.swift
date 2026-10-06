import CoreGraphics

func isClose(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 1e-6) -> Bool {
    abs(lhs - rhs) <= tolerance
}

func isClose(_ lhs: CGPoint, _ rhs: CGPoint, tolerance: CGFloat = 1e-6) -> Bool {
    isClose(lhs.x, rhs.x, tolerance: tolerance) && isClose(lhs.y, rhs.y, tolerance: tolerance)
}

func isClose(_ lhs: CGSize, _ rhs: CGSize, tolerance: CGFloat = 1e-6) -> Bool {
    isClose(lhs.width, rhs.width, tolerance: tolerance) && isClose(lhs.height, rhs.height, tolerance: tolerance)
}
