import LogisticsSystem "canister:logistics_system_backend";

import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import Nat "mo:base/Nat";
import Float "mo:base/Float";

actor LogisticsSystemTests {
    
    // ======================
    // Main Test Orchestrator
    // ======================
    
    public shared func runAllTests() : async Text {
        var results = "🚀 Starting Logistics System Tests\n\n";
        
        results #= await testWarehouseCapacity();
        results #= await testPackageLifecycle();
        results #= await testDriverWorkflow();
        results #= await testRouteOperations();
        results #= await testPriorityHandling();
        results #= await testErrorScenarios();
        
        results #= "\n✅ All Tests Completed Successfully";
        return results;
    };

    // ======================
    // Core Test Cases
    // ======================

    func testWarehouseCapacity() : async Text {
        try {
            // Setup
            let whId = await LogisticsSystem.addWarehouse("Central Hub", 2);
            let pkg1 = await createTestPackage();
            let pkg2 = await createTestPackage();
            let pkg3 = await createTestPackage();

            // Validate capacity enforcement
            assertOk(await LogisticsSystem.assignPackageToWarehouse(pkg1, whId));
            assertOk(await LogisticsSystem.assignPackageToWarehouse(pkg2, whId));
            assertErr(await LogisticsSystem.assignPackageToWarehouse(pkg3, whId));

            "✅ Warehouse Capacity Tests Passed\n";
        } catch e {
            "❌ Warehouse Capacity Tests Failed: " # debug_show(e) # "\n";
        }
    };

    func testPackageLifecycle() : async Text {
        try {
            // Create and validate package
            let pkgId = await createTestPackage();
            let package = await getPackage(pkgId);
            
            // Test state transitions
            assert package.status == #InWarehouse;
            assert package.priority == #Standard;

            // Test priority escalation
            assertOk(await LogisticsSystem.prioritizePackage(pkgId));
            let updatedPackage = await getPackage(pkgId);
            assert updatedPackage.priority == #Express;

            // Test rerouting
            assertOk(await LogisticsSystem.reroutePackage(pkgId, "New Destination"));
            let reroutedPackage = await getPackage(pkgId);
            assert reroutedPackage.destination == "New Destination";

            "✅ Package Lifecycle Tests Passed\n";
        } catch e {
            "❌ Package Lifecycle Tests Failed: " # debug_show(e) # "\n";
        }
    };

    func testDriverWorkflow() : async Text {
        try {
            // Setup driver and route
            let driverId = await LogisticsSystem.registerDriver("John Doe", #Van);
            let routeId = await LogisticsSystem.createRoute("Warehouse", "Downtown", 15.5);

            // Validate route operations
            assertOk(await LogisticsSystem.startRoute(routeId));
            assertOk(await LogisticsSystem.completeRoute(routeId));

            // Verify driver status
            let driver = await getDriver(driverId);
            assert driver.isAvailable;
            assert driver.completedRoutes.size() == 1;

            "✅ Driver Workflow Tests Passed\n";
        } catch e {
            "❌ Driver Workflow Tests Failed: " # debug_show(e) # "\n";
        }
    };

    func testRouteOperations() : async Text {
        try {
            // Create and validate route
            let routeId = await LogisticsSystem.createRoute("Port", "Airport", 42.8);
            let route = await getRoute(routeId);
            
            assert route.distanceKm == 42.8;
            assert route.estimatedDuration > 0;

            "✅ Route Operations Tests Passed\n";
        } catch e {
            "❌ Route Operations Tests Failed: " # debug_show(e) # "\n";
        }
    };

    func testPriorityHandling() : async Text {
        try {
            // Create test packages
            let standardPkg = await createTestPackage();
            let expressPkg = await createTestPackage();

            // Set priority
            assertOk(await LogisticsSystem.prioritizePackage(expressPkg));

            // Validate time estimates
            let standardTime = await LogisticsSystem.estimateDeliveryTime(standardPkg);
            let expressTime = await LogisticsSystem.estimateDeliveryTime(expressPkg);

            switch (standardTime, expressTime) {
                case (#ok std, #ok exp) assert exp < std;
                case _ { assert false };
            };

            "✅ Priority Handling Tests Passed\n";
        } catch e {
            "❌ Priority Handling Tests Failed: " # debug_show(e) # "\n";
        }
    };

    func testErrorScenarios() : async Text {
        try {
            // Test invalid IDs
            assertErr(await LogisticsSystem.assignPackageToWarehouse(9999, 9999));
            assertErr(await LogisticsSystem.prioritizePackage(9999));
            assertErr(await LogisticsSystem.startRoute(9999));

            "✅ Error Scenario Tests Passed\n";
        } catch e {
            "❌ Error Scenario Tests Failed: " # debug_show(e) # "\n";
        }
    };

    // ======================
    // Test Helpers
    // ======================

    private func createTestPackage() : async LogisticsSystem.PackageId {
        await LogisticsSystem.createPackage(
            1.5,                // weight
            "Origin",           // origin
            "Destination",      // destination
            #InWarehouse,       // initial status
            #Standard,          // default priority
            "+1234567890"       // customer phone
        )
    };

    private func getPackage(pkgId: LogisticsSystem.PackageId) : async LogisticsSystem.Package {
        switch (await LogisticsSystem.getPackage(pkgId)) {
            case (?pkg) pkg;
            case null { Debug.trap("Package not found: " # Nat.toText(pkgId)) };
        }
    };

    private func getDriver(driverId: LogisticsSystem.DriverId) : async LogisticsSystem.Driver {
        switch (await LogisticsSystem.getDriver(driverId)) {
            case (?driver) driver;
            case null { Debug.trap("Driver not found: " # Nat.toText(driverId)) };
        }
    };

    private func getRoute(routeId: LogisticsSystem.RouteId) : async LogisticsSystem.Route {
        switch (await LogisticsSystem.getRoute(routeId)) {
            case (?route) route;
            case null { Debug.trap("Route not found: " # Nat.toText(routeId)) };
        }
    };

    private func assertOk(result: Result.Result<Any, Text>) {
        switch result {
            case (#ok _) {};
            case (#err msg) { Debug.trap("Unexpected error: " # msg) };
        }
    };

    private func assertErr(result: Result.Result<Any, Text>) {
        switch result {
            case (#ok _) { Debug.trap("Expected error but got success") };
            case (#err _) {};
        }
    };
};