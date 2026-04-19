const admin = require('firebase-admin');

// ==================== LOCATION-SPECIFIC NAME LISTS ====================
const vostokgradNames = [
  'Dmitri', 'Nikolai', 'Luka', 'Damir', 'Lev', 'Maxim', 'Viktor', 'Mikhail', 'Vladimir',
  'Yakov', 'Andrei', 'Lenin', 'Mishka', 'Alexei', 'Boris', 'Bogdan', 'Konstantin', 'Igor',
  'Vladislav', 'Fedor', 'Miroslav', 'Nikolaj', 'Sergey', 'Vitaliy', 'Korvin', 'Sergei',
  'Fyodor', 'Stanislav', 'Vasily', 'Vyacheslav', 'Yuri', 'Yuriy', 'Valik', 'Grigori',
  'Gennadi', 'Pyotr', 'Yaroslav', 'Leo', 'Pavel', 'Alyosha', 'Grigor', 'Ivanovich',
  'Anton', 'Matvey', 'Aleks', 'Aleksandr', 'Daniil', 'Iosif', 'Kir', 'Ivann', 'Melor',
  'Oleg', 'Svetoslav'
];

const valleoraNames = [
  'Alejandro', 'Diego', 'Carlos', 'Juan', 'Mateo', 'Marcos', 'Lucas', 'Lucia', 'Angel',
  'Santiago', 'Jose', 'Juanito', 'Rafael', 'Alfonso', 'Jaime', 'Donato', 'Enrico', 'Jorge',
  'Nicanor', 'Rubio', 'Teofilo', 'Timoteo', 'Javier', 'Miguel', 'Marco', 'Antonio',
  'Alberto', 'Fernando', 'Pablo', 'Pedro', 'Manuel', 'Enrique', 'Andres', 'Raul',
  'Joaquin', 'Alonzo', 'Cristiano', 'Rodrigo', 'Vicente', 'Roberto', 'Gabriel', 'Ricardo',
  'Hugo', 'Julio', 'Tomas', 'Dario', 'Armando', 'Felipe', 'Rolando', 'Esteban', 'Arturo',
  'Gregorio', 'Álvaro', 'Isidro', 'Ignacio'
];

const riverstoneNames = [
  'Alex', 'Jermaine', 'Carl', 'John', 'Corey', 'Mark', 'Luke', 'Levi', 'Angelo', 'Jackson',
  'Joseph', 'Johnny', 'Warren', 'Carter', 'Jeremy', 'Donald', 'Eric', 'Mason', 'Dominic',
  'Sean', 'Harrison', 'Timmy', 'Hank', 'Will', 'Marvin', 'Anthony', 'Albert', 'Kevin',
  'Wyatt', 'Pete', 'Chuck', 'Quentin', 'Hunter', 'Cooper', 'Victor', 'Zack', 'Tony',
  'Michael', 'Jim', 'Wade', 'Chris', 'Dwayne', 'Nelson', 'Jules', 'Tommy', 'Frank',
  'Justin', 'Jared', 'Allen', 'Deontay', 'Darren'
];

const thornburyNames = [
  'Matthew', 'Kieran', 'Niall', 'Charlie', 'Charles', 'William', 'Harry', 'Barry', 'Nigel',
  'Andrew', 'Richard', 'Arthur', 'George', 'Liam', 'Oliver', 'Rowan', 'James', 'Henry',
  'Edward', 'Albert', 'Philip', 'Winston', 'Robert'
];

const otherNames = [
  'Aarav', 'Patel', 'Ishaan', 'Zaheer', 'Ravi', 'Amir', 'Tarak', 'Laksh', 'Deepak',
  'Sanjay', 'Sutchan', 'Akshat', 'Aveer', 'Keshav', 'Vidhart'
];

// ==================== DRIVER CLASS (SERVER-CONTROLLED) ====================
function generateRandomDriver(location, minDrivingSkill = 1) {
  let namePool;

  switch (location) {
    case "Vostokgrad":
      namePool = vostokgradNames;
      break;
    case "Valleora":
      namePool = valleoraNames;
      break;
    case "Riverstone":
      namePool = riverstoneNames;
      break;
    case "Thornbury":
      namePool = thornburyNames;
      break;
    default:
      namePool = otherNames;
  }

  const name = namePool[Math.floor(Math.random() * namePool.length)];

  return {
    name: name,
    drivingSkill: Math.floor(Math.random() * (33 - minDrivingSkill)) + minDrivingSkill,  // minDrivingSkill to 32
    salary: Math.floor(Math.random() * 471) + 30,
    potential: Math.floor(Math.random() * 20) + 1,      // remains 1-20
    weapon: null,
    health: 100,
  };
}

module.exports = {
  generateRandomDriver,
  // lists are exported only if you ever need them elsewhere
  vostokgradNames,
  valleoraNames,
  riverstoneNames,
  thornburyNames,
  otherNames
};