import Array "mo:base/Array";
import HashMap "mo:base/HashMap";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Result "mo:base/Result";
import Float "mo:base/Float";
import Iter "mo:base/Iter";
import Hash "mo:base/Hash";
import Debug "mo:base/Debug";
import Int "mo:base/Int";


actor LogisticsSystem {
  type PackageId = Nat;
  type WarehouseId = Nat;
  type DriverId = Nat;
  type RouteId = Nat;

  // ===== ENHANCED DATA STRUCTURES =====
  public type Package = {
    weight : Float;
    origin : Text;
    destination : Text;
    status : { #InWarehouse; #InTransit; #Delivered };
    priority : { #Standard; #Express };
    warehouseId : ?WarehouseId;
    routeId : ?RouteId;
    customerPhone : Text;
    createdTime : Int;
  };
  
  public type Warehouse = {
    location : Text;
    capacity : Nat;
    storedPackages : [PackageId];
  };

  public type Driver = {
    driverId : DriverId;
    completedRoutes : [RouteId];
    currentRoute : ?RouteId;
    isAvailable : Bool;
    name : Text;
    vehicleType : {#Bike; #Truck; #Van}
  };

  public type Route = {
    origin : Text;
    destination : Text;
    distanceKm : Float; // Real-world distance
    assignedDriver : ?DriverId;
    estimatedDuration : Nat; // Minutes
    startTime : ?Int;
    endTime : ?Int;
  };

  // ===== STATE WITH STABLE STORAGE =====
  stable var nextPackageId : PackageId = 0;
  stable var nextWarehouseId : WarehouseId = 0;
  stable var nextDriverId : DriverId = 0;
  stable var nextRouteId : RouteId = 0;
  // Custom Nat hashing
  func natHash(n : Nat) : Hash.Hash { Text.hash(Nat.toText(n)) };

  let packages = HashMap.HashMap<PackageId, Package>(0, Nat.equal, natHash);
  let warehouses = HashMap.HashMap<WarehouseId, Warehouse>(0, Nat.equal, natHash);
  let drivers = HashMap.HashMap<DriverId, Driver>(0, Nat.equal, natHash);
  let routes = HashMap.HashMap<RouteId, Route>(0, Nat.equal, natHash);

  // =====  CORE FUNCTIONS =====

  // 1. Add Warehouse with Capacity Checks
  public shared func addWarehouse(location : Text, capacity : Nat) : async WarehouseId {
    let warehouseId = nextWarehouseId;
    warehouses.put(warehouseId, {
      location = location;
      capacity = capacity;
      storedPackages = [];
    });
    nextWarehouseId += 1;
    warehouseId
  };
  public shared query func getPackage(packageId : PackageId) : async ?Package {
    packages.get(packageId)
};
  // 2. Assign Package to Warehouse with Capacity Validation
  public shared func assignPackageToWarehouse(
    packageId : PackageId,
    warehouseId : WarehouseId
  ) : async Result.Result<(), Text> {
    switch (packages.get(packageId), warehouses.get(warehouseId)) {
      case (null, _) { #err("Package not found") };
      case (_, null) { #err("Warehouse not found") };
      case (?pkg, ?wh) {
        if (wh.storedPackages.size() >= wh.capacity) {
          #err("Warehouse at capacity")
        } else {
          let updatedWh = {
            wh with
            storedPackages = Array.append(wh.storedPackages, [packageId])
          };
          warehouses.put(warehouseId, updatedWh);
          let updatedPkg = { pkg with warehouseId = ?warehouseId };
          packages.put(packageId, updatedPkg);
          #ok()
        }
      }
    }
  };

  // 3. Register New Driver with Availability
  public shared func registerDriver(
    name : Text,
    vehicleType : { #Truck; #Van; #Bike }
  ) : async DriverId {
    let driverId = nextDriverId;
    drivers.put(driverId, {
      driverId = driverId;  // Add this line
      name = name;
      vehicleType = vehicleType;
      isAvailable = true;
      currentRoute = null;
      completedRoutes = [];
    });
    nextDriverId += 1;
    driverId
  };

  // 4. Create New Delivery Route with Distance
  public shared func createRoute(
    origin : Text,
    destination : Text,
    distanceKm : Float
  ) : async RouteId {
    let routeId = nextRouteId;
    routes.put(routeId, {
      origin = origin;
      destination = destination;
      distanceKm = distanceKm;
      assignedDriver = null;
      estimatedDuration = calculateEstimatedTime(distanceKm);
      startTime = null;
      endTime = null;
    });
    nextRouteId += 1;
    routeId
  };

  // 5. Calculate Optimal Route (Simplified)
  private func _calculateOptimalRoute(
    origin : Text,
    destination : Text
  ) : Float {
    // Mock distance calculation (real implementation would use geocoding)
    let baseDistance = 50.0; // Default 50km
    if (origin == "Downtown" and destination == "Airport") 75.0
    else if (origin == "Port" and destination == "Warehouse") 20.0
    else baseDistance
  };

  // 6. Prioritize Package for Express Delivery
  public shared func prioritizePackage(packageId : PackageId) : async Result.Result<(), Text> {
    switch (packages.get(packageId)) {
      case (null) { #err("Package not found") };
      case (?pkg) {
        let updated = { pkg with priority = #Express };
        packages.put(packageId, updated);
        #ok()
      }
    }
  };

  // 7. Reroute Package to New Destination
  public shared func reroutePackage(
    packageId : PackageId,
    newDestination : Text
  ) : async Result.Result<(), Text> {
    switch (packages.get(packageId)) {
      case (null) { #err("Package not found") };
      case (?pkg) {
        let updated = { pkg with destination = newDestination };
        packages.put(packageId, updated);
        // Invalidate existing route
        switch (pkg.routeId) {
          case (null) {};
          case (?rid) {
            switch (routes.get(rid)) {
              case (null) {};
              case (?route) {
                let updatedRoute = { route with destination = newDestination };
                routes.put(rid, updatedRoute)
              }
            }
          }
        };
        #ok()
      }
    }
  };

  // 8. Start Delivery Route (Driver Departure)
  public shared func startRoute(routeId : RouteId) : async Result.Result<(), Text> {
    switch (routes.get(routeId), drivers.get(getDriverIdFromRoute(routeId))) {
      case (null, _) { #err("Route not found") };
      case (?route, ?driver) {
        if (not driver.isAvailable) {
          #err("Driver already occupied")
        } else {
          let updatedDriver = { driver with
            isAvailable = false;
            currentRoute = ?routeId;
          };
          drivers.put(driver.driverId, updatedDriver);
          let updatedRoute = { route with
            startTime = ?Time.now();
          };
          routes.put(routeId, updatedRoute);
          #ok()
        }
      };
      case _ { #err("Invalid state") }
    }
  };

  // 9. Complete Delivery Route (Finalize)
  public shared func completeRoute(routeId : RouteId) : async Result.Result<(), Text> {
    switch (routes.get(routeId)) {
      case (null) { #err("Route not found") };
      case (?route) {
        // Update route end time
        let updatedRoute = { route with endTime = ?Time.now() };
        routes.put(routeId, updatedRoute);
        
        // Free driver
        switch (route.assignedDriver) {
          case (null) {};
          case (?did) {
            switch (drivers.get(did)) {
              case (null) {};
              case (?driver) {
                let updatedDriver = { driver with
                  isAvailable = true;
                  currentRoute = null;
                  completedRoutes = Array.append(driver.completedRoutes, [routeId])
                };
                drivers.put(did, updatedDriver)
              }
            }
          }
        };
        
        // Update all packages on this route to Delivered
        for ((pid, pkg) in packages.entries()) {
          if (pkg.routeId == ?routeId) {
            let updated = { pkg with status = #Delivered };
            packages.put(pid, updated)
          }
        };
        #ok()
      }
    }
  };

  // 10. Estimate Delivery Time with Priority Consideration
  public shared func estimateDeliveryTime(packageId : PackageId) : async Result.Result<Int, Text> {
    switch (packages.get(packageId)) {
      case (null) { #err("Package not found") };
      case (?pkg) {
        switch (pkg.routeId) {
          case (null) { #err("No route assigned") };
          case (?rid) {
            switch (routes.get(rid)) {
              case (null) { #err("Route not found") };
              case (?route) {
                let baseTime = route.estimatedDuration * 60; // Convert to seconds
                let adjustedTime = switch (pkg.priority) {
                  case (#Standard) baseTime;
                  case (#Express) (Float.toInt(Float.fromInt(baseTime) * 0.7)) // 30% faster
                };
                #ok(adjustedTime)
              }
            }
          }
        }
      }
    }
  };
  
  // 11. Send Delivery Notification (Mock)
  public shared func sendDeliveryNotification(packageId : PackageId) : async Result.Result<(), Text> {
    switch (packages.get(packageId)) {
      case (null) { #err("Package not found") };
      case (?pkg) {
        // In real system: Integrate with SMS/email service
        Debug.print("Notification sent to " # pkg.customerPhone);
        #ok()
      }
    }
  };
  // 13. Create a New Package
  public shared func createPackage(
    weight : Float,
    origin : Text,
    destination : Text,
    status : { #InWarehouse; #InTransit; #Delivered },
    priority : { #Standard; #Express },
    customerPhone : Text
  ) : async PackageId {
    let packageId = nextPackageId;
    let newPackage = {
      weight = weight;
      origin = origin;
      destination = destination;
      status = status;
      priority = priority;
      warehouseId = null; // Initially, no warehouse assigned
      routeId = null; // Initially, no route assigned
      customerPhone = customerPhone;
      createdTime = Time.now();
    };
    packages.put(packageId, newPackage);
    nextPackageId += 1;
    packageId
  };

  
  // 12. Generate Monthly Delivery Report 
  public shared func generateDeliveryReport(month : Nat, year : Nat) : async [{ packageId : PackageId; deliveredTime : Int }] {
    let now = Time.now();
    let secondsInDay = 86400_000_000_000;
    let daysInMonth = 30; // Approximation, you might want to implement a more accurate calculation
    
    let start = now - Int.abs(year - 2023) * 365 * secondsInDay - (12 - month) * daysInMonth * secondsInDay;
    let end = start + daysInMonth * secondsInDay;
    
    Array.map<PackageId, { packageId : PackageId; deliveredTime : Int }>(
      Array.filter<PackageId>(
        Iter.toArray(packages.keys()),
        func(pid) : Bool {
          switch (packages.get(pid)) {
            case (?pkg) {
              pkg.status == #Delivered and pkg.createdTime >= start and pkg.createdTime < end
            };
            case null { false }
          }
        }
      ),
      func(pid) : { packageId : PackageId; deliveredTime : Int } {
        let pkg = switch (packages.get(pid)) {
          case (?p) p;
          case null { assert false; loop {} };
        };
        { packageId = pid; deliveredTime = pkg.createdTime }
      }
    )
};

  // ===== HELPER FUNCTIONS =====
  private func calculateEstimatedTime(distanceKm : Float) : Nat {
    // Assumes average speed of 60 km/h
    Int.abs(Float.toInt(distanceKm / 60.0 * 60.0)) // Convert hours to minutes and ensure positive
};

  private func getDriverIdFromRoute(_routeId : RouteId) : DriverId {
    // Implement logic to find driver assigned to route
    0 // Simplified for example
  };
};


