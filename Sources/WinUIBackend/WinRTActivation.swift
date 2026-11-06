import CWinRT
import WinSDK
import WindowsFoundation

// swift-winrt 0.5.0 shipped these two in WindowsFoundation. 0.6.0, which the
// bindings moved to with Windows App SDK 2.6.5 (2026-11-05), dropped
// RoActivateInstance and narrowed RoGetActivationFactory to a StaticString, while
// the backend activates classes whose names are only known at run time. Same
// bodies as the 0.5.0 versions, except that the C calls go through CWinRT's
// *_Workaround entry points, which take the GUID_Workaround that IID now is.
// swift-winrt 0.5.0 在 WindowsFoundation 中提供這兩個函式。bindings 隨 Windows App
// SDK 2.6.5 改用 0.6.0（2026-11-05）後，RoActivateInstance 被移除，
// RoGetActivationFactory 也只接受 StaticString；而 backend 要啟用的類別名稱有些
// 到執行期才知道。函式本體與 0.5.0 版相同，只是 C 呼叫改走 CWinRT 的 *_Workaround
// 進入點，因為 IID 現在是 GUID_Workaround。

func RoGetActivationFactory<Factory: WindowsFoundation.IInspectable>(
    _ activatableClassId: HString
) throws -> Factory {
    var iid = Factory.IID
    let (factory) = try ComPtrs.initialize(to: C_IInspectable.self) { factoryAbi in
        try CHECKED(CWinRT.RoGetActivationFactory_Workaround(activatableClassId.get(), &iid, &factoryAbi))
    }
    return try factory!.queryInterface()
}

func RoActivateInstance<Instance: WindowsFoundation.IInspectable>(
    _ activatableClassId: HString
) throws -> Instance {
    let (instance) = try ComPtrs.initialize { instanceAbi in
        try CHECKED(CWinRT.RoActivateInstance_Workaround(activatableClassId.get(), &instanceAbi))
    }
    return try instance!.queryInterface()
}
