module main;

import std.stdio;
import std.typecons;
import std.csv;
import std.file;
import std.array;
import std.string;
import std.conv;
import std.algorithm.searching;
import std.math;

const float amind=60; //mindest Abstand, muss bei einem Fahrrad circa 60cm sein (Lenker und Aussenspiegel)
const float amax=1400; //Grenze muss hoeher gesetzt werden, aber tests wurden in kleiner Wohnung durchgefuehrt

const float amaxuber=400;
const float lower=0.95;
const float higher=1.05;
const int empfindlichkeit=15;
const int empfindlichkeitstart=1;
const float mindanachuber=1000;
const float strasse =250.0;//Strassenbreite

int globalcount=0;
struct measuredata{
    int number;
    float time;
    float vorne;
    float hinten;
    float utctime;
    float north;
    float east;
    float date;
    float speed;
    float orientation=-1.0;
    float temp=17.0;

    float overtaking;
    float speedKFZ;
    float lenghtKFZ;
};

struct geodata{
    float utctime;
    float north;
    float east;
};


struct fahrt{
    measuredata[] inputdata;
    geodata[] geodaten;
    float gesamtstrecke;
    measuredata[] overtaking;
};

fahrt current_drive;
float[][]readdata; //alle Messwerte
float[][]gpsdata;

int countentiredata;
fahrt[] entiredata;

float coordinateconvert(string eingang){
    float startvalue=to!double(eingang);
    int intvalue=to!int(startvalue/100);
    float floatvalue=startvalue-intvalue*100;
    float returnvalue=intvalue+floatvalue/60;
    return returnvalue;
}

measuredata[] readcsv(string filename){//CSV-Datei einlesen
    measuredata[] inputdata;
    File file=File(filename, "r"); //Dateiname kommt aus Hauptprogramm
    float utctime;
    float north;
    float east;
    float date;
    float speed;
    float orientation=-1.0;
    float temp=17.0;
    float oldutctime;

    while(!file.eof()){ //Es wird immer bis zum Dateiende gelesen
        globalcount++; //Zahler fur alle Zeilen

        string line=file.readln();//Einzelne Zeile Einlesen als String
        if(canFind(line,"Temperatur")){
            auto split1=line.split(",");
            temp=to!double(split1[1]);
        }else if(count(line,",")>2){ //Die letzte Zeile jeder Datei ist leer, deshalb nur die vollen Zeilen verwenden
            auto split1=line.split(",");//Da es sich um eine CSV-Datei handelt Spalten an Kommata auftrennen
            //write(split1);//Ausgabe der aufgetrennten Zeile
            //writeln("test");//useless
            if(split1[0]=="GPS" || canFind(line, "N") || canFind(line, "*") || canFind(line, "E") || canFind(line, "V") || canFind(line,"F") || canFind(line,"C") || canFind(line,"B") || canFind(line, "GPRMC")){//Zeile wird als GPS-Inhalt erkannt und gesondert behandelt
                if(canFind(line,"GPRMC")==1){
                    auto splitgps=line.split(",");
                    if(splitgps[2]=="A"){
                        oldutctime=utctime;
                        utctime=to!double(splitgps[1]);
                        if(splitgps[4]=="N"){
                            north=coordinateconvert(splitgps[3]);
                        }
                        if(splitgps[4]=="S"){
                            north=-1*coordinateconvert(splitgps[3]);
                        }
                        if(splitgps[6]=="E"){
                            east=coordinateconvert(splitgps[5]);
                        }
                        if(splitgps[6]=="W"){
                            east=-1*coordinateconvert(splitgps[5]);
                        }
                        float speedk=to!double(splitgps[7]);
                        speed=speedk/0.53996;
                        date=to!double(splitgps[9]);
                        if(splitgps[8]!=""){
                            orientation=to!double(splitgps[8]);
                        }
                        else{
                            orientation=-1.0;
                        }

                    }
                    //write(splitgps);
                    if(utctime-oldutctime<0||utctime-oldutctime>150){
                        current_drive=automatisch_erkennen(current_drive);
                        entiredata~=current_drive;
                        destroy(current_drive);
                        //current_drive=[];
                    }
                    geodata newgeodata;
                    newgeodata.utctime=utctime;
                    newgeodata.north=north;
                    newgeodata.east=east;
                    current_drive.geodaten~=newgeodata;
                }
            }else{//Zeile enthalt normale Messwerte, nicht GPS
                auto splittime1=(split1[0]).split(" ");
                double time=0;
                int leerzeichenout;
                for(int leerzeichen; (splittime1[leerzeichen])=="";leerzeichen++){
                    leerzeichenout=leerzeichen+1;
                    //write(leerzeichen);
                }
                if(canFind(splittime1, "\n")){}
                else{
                    time=to!double(splittime1[leerzeichenout]);
                    auto split2=(split1[1]).split(" ");
                    auto split3=(split1[2]).split(" ");
                    if(split2[0]!=""&&split3[0]!=""){
                        double f1=to!double(split2[0]); //hinten
                        double f2=to!double(split3[0]); //vorne
                        if(f1>amind&&f2>amind&&f1<amax&&f2<amax){//Distanz kleiner mindestanforderung, also auserhalb Fahrradlenker oder groesser wie maximalmoeglich, technische Grenze HC-SR04 oder Begrenzgung der Testumgebung: delete
                            measuredata input;
                            input.time=time;
                            input.vorne=f1;
                            input.hinten=f2;
                            input.utctime=utctime;
                            input.north=north;
                            input.east=east;
                            input.date=date;
                            input.temp=temp;
                            input.speed=speed;
                            input.orientation=orientation;
                            inputdata~=input;
                            current_drive.inputdata~=input;
                        }
                    }
                }
            }
        }

    }
    file.close();
    return inputdata;
}

fahrt automatisch_erkennen(fahrt aktuelle_fahrt){
    aktuelle_fahrt.inputdata=glattung(aktuelle_fahrt.inputdata);
    aktuelle_fahrt.overtaking=erkennen(aktuelle_fahrt.inputdata);
    aktuelle_fahrt.gesamtstrecke=calcualtedistance(aktuelle_fahrt.geodaten);
    aktuelle_fahrt.inputdata=null;
    aktuelle_fahrt.geodaten=null;
    return aktuelle_fahrt;
}

measuredata[]glattung(measuredata[] ret){
    int zeilen=count(ret);
    float faktor=0.9;
    float faktor2=1.1;
    for(int i=1; i<(zeilen-1);i++){
        if((ret[i-1].vorne*faktor)>ret[i].vorne && (faktor*ret[i+1].vorne)>ret[i].vorne){
            ret[i].vorne=(ret[i-1].vorne+ret[i+1].vorne)/2;
        }
        if((ret[i-1].hinten*faktor)>ret[i].hinten && (faktor*ret[i+1].hinten)>ret[i].hinten){
            ret[i].hinten=(ret[i-1].hinten+ret[i+1].hinten)/2;
        }
        if((ret[i-1].vorne*faktor2)<ret[i].vorne && (faktor2*ret[i+1].vorne)<ret[i].vorne){
            ret[i].vorne=(ret[i-1].vorne+ret[i+1].vorne)/2;
        }
        if((ret[i-1].hinten*faktor2)<ret[i].hinten && (faktor2*ret[i+1].hinten)<ret[i].hinten){
            ret[i].hinten=(ret[i-1].hinten+ret[i+1].hinten)/2;
        }
    }

    return ret;
}

int writecsv(string filename, float[][]writeit){ //UP zur Ausgabe einer CSV-Datei, Name wird in Main angegeben -- automatisch adaptierte Breite
    int zeilencount;
    File file=File(filename,"w");
    foreach(i;writeit){
        int zeilencount2;
        foreach(j;writeit[zeilencount]){
            file.write(writeit[zeilencount][zeilencount2],",");
            zeilencount2++;
        }
        file.write("\n");
        zeilencount++;
    }
    file.close();
    return zeilencount;
}

int writecsvfromstruct(string filename,measuredata[] inputdata, bool inorub){
    File f=File(filename,"w");
    if(inorub){
        f.writeln("Zeitstempel,vorne,hinten,temp,Zeit,Datum,Lange,Breite,Geschw,Orientierung");
        foreach(measuredata input; inputdata){
            f.write(input.time,",");
            f.write(input.vorne,",");
            f.write(input.hinten,",");
            f.write(input.temp,",");
            f.write(input.utctime,",");
            f.write(input.date,",");
            f.write(input.north,",");
            f.write(input.east,",");
            f.write(input.speed,",");
            f.write(input.orientation,",");
            f.write("\n");
        }
    }else{
        f.writeln("Abstand,Zeit,Datum,Lange,Breite,Geschwindigkeit Fahrrad, Geschwindigkeit KFZ, Lange KFZ,");
        foreach(measuredata input; inputdata){
            f.write(input.overtaking,",");
            f.write(input.utctime,",");
            f.write(input.date,",");
            f.write(input.north,",");
            f.write(input.east,",");
            f.write(input.speed,",");
            f.write(input.speedKFZ,",");
            f.write(input.lenghtKFZ,",");
            f.write("\n");
        }
    }
    f.close();
    return 100;
}
int writecsv2(string filename, float[][]writeit){ //UP zur Ausgabe einer CSV-Datei, Name wird in Main angegeben
    int zeilencount;
    File file=File(filename,"w");
    foreach(i;writeit){
        file.writeln(writeit[zeilencount][0],",",writeit[zeilencount][1],",",writeit[zeilencount][2],",",writeit[zeilencount][3],",",writeit[zeilencount][4],",",writeit[zeilencount][5],",",writeit[zeilencount][6],",",writeit[zeilencount][7]);
        zeilencount++;
    }
    file.close();
    return zeilencount;
}

measuredata[] erkennen(measuredata[]inputdata){
    measuredata[] erkannt;
    float[] uberhol;
    float amindest=strasse+amind;
    int flaguber;
    int flaguber2;
    int flagunter;
    float lastuberholtime=0;
    float begin1;
    float end1;
    foreach(measuredata input; inputdata){
        float vorne=input.vorne;
        float hinten=input.hinten;

        if((input.time)>20.0){//alles innerhalb der ersten 20 Sekunden wird nicht berucksichtigt
            if( (vorne*higher<hinten) && vorne<amindest ){ //vorderer Wert ist um uber 40 Prozent kleiner als hinterer, uberholvorgang erst ab 2,5m erkennen
                if(flaguber==0){
                    begin1=input.time;
                }
                flaguber++; //Marker setzen
                flagunter=0;
            }else if( (hinten<amindest) && (vorne<amindest) && (flaguber>empfindlichkeitstart) && (hinten*lower)<vorne && (hinten*higher)>vorne ){
                if(flaguber2==0){
                    end1=input.time;
                }
                uberhol~=(vorne+hinten)/2;
                flaguber2++;
                flagunter=0;
            }else if( (vorne*lower)>hinten && (vorne>amindest) && (flaguber2>empfindlichkeit) ){
                int numberarr=uberhol.count();
                float gesamtuberhol=0;
                for(int zeilencount; zeilencount<numberarr; zeilencount++){
                    gesamtuberhol=gesamtuberhol+uberhol[zeilencount];
                }
                float timeforspeed=end1-begin1;
                float timeforlength=input.time-end1;
                float overtaking=gesamtuberhol/numberarr;
                float distanceforspeed=overtaking/20;
                float speed=(distanceforspeed)/timeforspeed;
                float length=(speed*timeforlength)/25;

                measuredata erkannt1;
                erkannt1=input;
                erkannt1.speedKFZ=input.speed+speed;
                erkannt1.lenghtKFZ=length;
                erkannt1.overtaking=overtaking;
                //erkannt1.speedKFZ=flaguber;
                //erkannt1.lenghtKFZ=bearbeitet[i][3];
                float timediff=input.time-lastuberholtime;
                if(numberarr>3 && input.time-lastuberholtime>1){
                    erkannt~=erkannt1;
                }
                uberhol.destroy();
                lastuberholtime=input.time;
                //erkannt~=bearbeitet[i-flaguber2/2];
                flaguber=0;
                flaguber2=0;
            }else{
                flagunter++;
            }
            if(flagunter>50){
                flaguber=0;
                flaguber2=0;
                flagunter=0;
            }
        }

    }
    return erkannt;
}

float calcualtedistance(geodata[] geodatafordistance){
    float drivendistance=0;
    int numberofdata=count(geodatafordistance);
    //writeln(numberofdata);
    for(int i=0; i<numberofdata-1;i++){
        float timedif=geodatafordistance[i+1].utctime-geodatafordistance[i].utctime;
        //writeln(timedif);
        if(timedif>0&&timedif<50){
            float eastdif=geodatafordistance[i+1].east-geodatafordistance[i].east;
            float northdif=geodatafordistance[i+1].north-geodatafordistance[i].north;
            float eastdifcos=eastdif*cos(geodatafordistance[i].north);
            float dist=111.3*sqrt(northdif*northdif+eastdifcos*eastdifcos);
            //writeln(dist);
            drivendistance=drivendistance+dist;
        }
    }
    return drivendistance;
}

void geojsonline(string filename, float[][]writeit){
    int zeilencount;
    File file=File(filename,"w");
    file.writeln("{");
    file.writeln("\"type\": \"FeatureCollection\",");
    file.writeln("\"features\": [");
    file.writeln("{");
    file.writeln("\"type\": \"Feature\",");
    file.writeln("\"properties\":{},");
    file.writeln("\"geometry\":{");
    file.writeln("\"type\": \"LineString\",");
    file.writeln("\"coordinates\":[");
    foreach(i;writeit){
        float north=writeit[zeilencount][3];
        float east=writeit[zeilencount][4];
        float abstand=writeit[zeilencount][0];
        if(north<90.0 && east<180.0 && abstand<amaxuber && abstand>amind/*&& writeit[zeilencount][2]<amaxuber*/){
            file.writeln("[");
            file.writeln(east,",");
            file.writeln(north);
            file.writeln("],");
        }
        zeilencount++;
    }
    file.writeln("]");
    file.writeln("}");
    file.writeln("}");
    file.writeln("]");
    file.writeln("}");
}

int writegeojson(string filename, measuredata[] writedata){
    int zeilencount;
    File file=File(filename,"w");
    file.writeln("{");
    file.writeln("\"type\": \"FeatureCollection\",");
    file.writeln("\"features\": [");
    foreach(measuredata writedat; writedata){
        float north=writedat.north;
        float east=writedat.east;
        float abstand=writedat.overtaking;
        if(north<90.0 && east<180.0 && abstand<amaxuber && abstand>amind/*&& writeit[zeilencount][2]<amaxuber*/){
            file.writeln("{");
            file.writeln("\"type\": \"Feature\",");
            file.writeln("\"properties\": {");
            //writeln(abstand);
            if(abstand<(amind+50)){
                file.writeln("\"marker-color\": \"#930000\"");
            }
            if( abstand<(amind+100) && abstand>(amind+50)){
                file.writeln("\"marker-color\": \"#e2001a\"");
            }
            if(abstand<(amind+150) && abstand>(amind+100)){
                file.writeln("\"marker-color\": \"#ffff00\"");
            }
            if(abstand>(amind+150)){
                file.writeln("\"marker-color\": \"#46812b\"");
            }
            file.writeln("},");
            file.writeln("\"geometry\": {");
            file.writeln("\"type\": \"Point\",");
            file.writeln("\"coordinates\": [");
            file.writeln(east, ",");
            file.writeln(north);
            file.writeln("]");
            file.writeln("}");
            file.writeln("},");
        }
        zeilencount++;
    }
    file.writeln("]");
    file.writeln("}");
    return zeilencount;
}

int writegeojsoneinfach(string filename, measuredata[] writedata){
    float[][]green;
    float[][]yellow;
    float[][]red;
    float[][]darkred;
    foreach(measuredata writedat; writedata){
        float north=writedat.north;
        float east=writedat.east;
        float abstand=writedat.overtaking;
        if(north<90.0 && east<180.0 && abstand<amaxuber && abstand>amind/*&& writeit[zeilencount][2]<amaxuber*/){
            if(abstand<(amind+50)){
                darkred~=[north,east];
            }else if( abstand<(amind+100) && abstand>(amind+50)){
                red~=[north,east];
            }else if(abstand<(amind+150) && abstand>(amind+100)){
                yellow~=[north,east];
            }else if(abstand>(amind+150)){
                green~=[north,east];
            }
        }
    }

    File file=File(filename,"w");
    file.writeln("{");//Gesamtklammer
    file.writeln("\"type\": \"FeatureCollection\",");
    file.writeln("\"features\": [");//allFeatures

    file.writeln("{");//erstes Feature
    file.writeln("\"type\": \"Feature\",");
    file.writeln("\"properties\": {\"marker-color\": \"#930000\"},");
    file.writeln("\"geometry\":{");//geometry klammer
    file.writeln("\"type\": \"MultiPoint\",");
    file.writeln("\"coordinates\": [");//Koordinaten
    foreach(int i, float[]coordinates; darkred){
        if(i<count(darkred)-1){
            file.writeln("[",coordinates[1],",",coordinates[0],"],");
        }else{
            file.writeln("[",coordinates[1],",",coordinates[0],"]");
        }
    }
    file.writeln("]");//Koordinaten
    file.writeln("}");//geometry
    file.writeln("},");//erstes Feature

    file.writeln("{");//zweites Feature
    file.writeln("\"type\": \"Feature\",");
    file.writeln("\"properties\": {\"marker-color\": \"#e2001a\"},");
    file.writeln("\"geometry\":{");//geometry klammer
    file.writeln("\"type\": \"MultiPoint\",");
    file.writeln("\"coordinates\": [");//Koordinaten
    foreach(int i, float[]coordinates; red){
        if(i<count(red)-1){
            file.writeln("[",coordinates[1],",",coordinates[0],"],");
        }else{
            file.writeln("[",coordinates[1],",",coordinates[0],"]");
        }
    }
    file.writeln("]");//Koordinaten
    file.writeln("}");//geometry
    file.writeln("},");//zweites Feature

    file.writeln("{");//drittes Feature
    file.writeln("\"type\": \"Feature\",");
    file.writeln("\"properties\": {\"marker-color\": \"#ffff00\"},");
    file.writeln("\"geometry\":{");//geometry klammer
    file.writeln("\"type\": \"MultiPoint\",");
    file.writeln("\"coordinates\": [");//Koordinaten
    foreach(int i, float[]coordinates; yellow){
        if(i<count(yellow)-1){
            file.writeln("[",coordinates[1],",",coordinates[0],"],");
        }else{
            file.writeln("[",coordinates[1],",",coordinates[0],"]");
        }
    }
    file.writeln("]");//Koordinaten
    file.writeln("}");//geometry
    file.writeln("},");//drittes Feature

    file.writeln("{");//viertes Feature
    file.writeln("\"type\": \"Feature\",");
    file.writeln("\"properties\": {\"marker-color\": \"#46812b\"},");
    file.writeln("\"geometry\":{");//geometry klammer
    file.writeln("\"type\": \"MultiPoint\",");
    file.writeln("\"coordinates\": [");//Koordinaten
    foreach(int i, float[]coordinates; green){
        if(i<count(green)-1){
            file.writeln("[",coordinates[1],",",coordinates[0],"],");
        }else{
            file.writeln("[",coordinates[1],",",coordinates[0],"]");
        }
    }
    file.writeln("]");//Koordinaten
    file.writeln("}");//geometry
    file.writeln("}");//viertes Feature

    file.writeln("]");//allFeatures schliessen
    file.writeln("}");//Gesamtklammer schliessen
    return 100;
}

int main(string[] args)
{
    int x=0;

    string filenumber=to!string(x);
    string filename=join(["messdaten",filenumber,".txt"]);
    while(exists(filename)){
        //write(filename);
        auto inputdata=readcsv(filename);
        x++;
        filenumber=to!string(x);
        filename=join(["messdaten",filenumber,".txt"]);
        //write(filename);
    }
    if(count(current_drive.inputdata)!=0){
        current_drive=automatisch_erkennen(current_drive);
        entiredata~=current_drive;
        destroy(current_drive);
    }
    //int intret=writecsvfromstruct("messdaten000.csv", inputdata, true);
    //writeln("Es wurden ",intret," Zeilen geschrieben");

    //measuredata[] overtakedata=erkennen(inputdata);
    measuredata[]overtakedata;
    float gesamtdistanz=0;
    //writeln(count(entiredata));
    foreach(int i,fahrt aktuelle_fahrt;entiredata){
        overtakedata~=aktuelle_fahrt.overtaking;
        gesamtdistanz=gesamtdistanz+aktuelle_fahrt.gesamtstrecke;
        destroy(entiredata[i]);
    }
    writeln(gesamtdistanz);
    int intret2=writecsvfromstruct("erkannte.csv", overtakedata, false);
    int intret4=writegeojson("Geodata_overtake.geojson",overtakedata);
    int intret6=writegeojsoneinfach("Geodata_overtake_simple.geojson",overtakedata);
    writeln(intret2,"       ",intret4);
    //geojsonline("line.geojson",ret);

	return 0;
}