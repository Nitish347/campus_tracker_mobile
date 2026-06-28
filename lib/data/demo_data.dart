import '../domain/entities/driver.dart';
import '../domain/entities/gps_point.dart';
import '../domain/entities/student.dart';
import '../domain/entities/vehicle.dart';

const demoVehicles = [
  Vehicle(
    id: 'BUS-04',
    plate: 'DL 1PC 4182',
    driver: 'Ramesh Kumar',
    route: 'North Loop',
    speed: 38,
    status: 'On route',
    students: 22,
  ),
  Vehicle(
    id: 'BUS-07',
    plate: 'DL 1PC 5721',
    driver: 'Sunil Yadav',
    route: 'East Park',
    speed: 24,
    status: 'On route',
    students: 18,
  ),
  Vehicle(
    id: 'VAN-02',
    plate: 'DL 1VC 9044',
    driver: 'Amit Singh',
    route: 'South City',
    speed: 0,
    status: 'At school',
    students: 12,
  ),
];

const demoStudents = [
  Student(
    id: 1,
    name: 'Kaira Khandelwal',
    regNo: 'JPIS/5441/25',
    className: 'Grade 4',
    phone: '7568089869',
    secondaryPhone: '7568089869',
    vehicle: 'BUS-04',
    area: 'Burmese Colony',
  ),
  Student(
    id: 2,
    name: 'Aryadit Agarwal',
    regNo: 'JPIS/4768/23',
    className: 'Grade 4',
    phone: '9829919869',
    secondaryPhone: '',
    vehicle: 'BUS-04',
    area: 'Adarsh Nagar',
  ),
  Student(
    id: 3,
    name: 'Maurya Dhariwal',
    regNo: 'JPIS/4765/23',
    className: 'Grade 4',
    phone: '9829009228',
    secondaryPhone: '9928889228',
    vehicle: 'BUS-07',
    area: 'Adarsh Nagar',
  ),
];

const demoDrivers = [
  Driver(
    id: 1,
    name: 'Ramesh Kumar',
    phone: '9810724561',
    vehicle: 'BUS-04',
    route: 'North Loop',
  ),
  Driver(
    id: 2,
    name: 'Sunil Yadav',
    phone: '9958410882',
    vehicle: 'BUS-07',
    route: 'East Park',
  ),
  Driver(
    id: 3,
    name: 'Amit Singh',
    phone: '9871354119',
    vehicle: 'VAN-02',
    route: 'South City',
  ),
];

final demoGps = [
  GpsPoint(
    vehicleNo: 'BUS-04',
    latitude: 26.9124,
    longitude: 75.7873,
    speed: 38,
    ignition: true,
    odometer: 12718.58,
    timestamp: DateTime.now(),
    alias: 'North Loop',
    imei: 'demo-001',
  ),
  GpsPoint(
    vehicleNo: 'BUS-07',
    latitude: 26.8467,
    longitude: 75.8009,
    speed: 24,
    ignition: true,
    odometer: 215.93,
    timestamp: DateTime.now(),
    alias: 'East Park',
    imei: 'demo-002',
  ),
];
